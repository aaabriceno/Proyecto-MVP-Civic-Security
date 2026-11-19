defmodule Civic.Validation do
  @moduledoc """
  Validación comunitaria: las personas cercanas confirman o niegan un reporte.

  Reglas (ver docs/arquitectura-mvp.md):

    * solo votan cuentas **verificadas** (con DNI): una persona, una cuenta;
    * nadie vota su **propio** reporte;
    * hay que estar a menos de `radius_m` (1 km) del lugar; la ubicación del
      votante se usa solo para eso y **no se guarda**;
    * una cuenta vota **una sola vez** por reporte y no puede cambiar su voto;
    * al llegar a `threshold` (3) confirmaciones el reporte pasa a **Verificado**;
      al llegar a `threshold` votos "es falso", a **Descartado**. Después de eso
      el reporte ya no recibe votos.

  De cada voto solo se guarda `HMAC(k_vote, cuenta ‖ incidente)` (ver
  `Civic.Privacy`), nunca la cuenta.

  El reporte se lee con `FOR UPDATE`: dos votos simultáneos se atienden uno tras
  otro, así que nunca hay un "cuarto voto" ni dos cambios de estado.
  """

  import Ecto.Query

  alias Civic.Accounts.User
  alias Civic.Incidents.Incident
  alias Civic.Privacy
  alias Civic.Repo
  alias Civic.Validation.Vote

  @valores %{"confirmo" => :confirmo, "falso" => :falso}

  @type error ::
          :not_found
          | :not_verified
          | :own_report
          | :voting_closed
          | :too_far
          | :already_voted
          | :invalid_vote
          | :invalid_location

  @doc "Cuántos votos del mismo tipo hacen falta para cambiar el estado."
  @spec threshold() :: pos_integer()
  def threshold, do: config(:threshold)

  @doc "Distancia máxima, en metros, entre quien vota y el reporte."
  @spec radius_m() :: pos_integer()
  def radius_m, do: config(:radius_m)

  @doc """
  Registra el voto de `user` sobre el reporte `incident_id`.

  `valor` es `"confirmo"` o `"falso"`; `lat`/`lng` son dónde está quien vota.
  Devuelve `{:ok, incidente_actualizado}` o `{:error, razón}` (ver `t:error/0`).

  Opciones (para pruebas y demostraciones): `:threshold` y `:radius_m`.
  """
  @spec vote(User.t(), term(), term(), term(), term(), keyword()) ::
          {:ok, Incident.t()} | {:error, error()}
  def vote(%User{} = user, incident_id, valor, lat, lng, opts \\ []) do
    with {:ok, valor} <- cast_valor(valor),
         {:ok, {lat, lng}} <- cast_location(lat, lng),
         :ok <- check_verified(user),
         {:ok, id} <- cast_id(incident_id) do
      cast_vote(user, id, valor, {lat, lng}, opts)
    end
  end

  defp cast_vote(user, id, valor, {lat, lng}, opts) do
    threshold = Keyword.get_lazy(opts, :threshold, &threshold/0)
    radius_m = Keyword.get_lazy(opts, :radius_m, &radius_m/0)

    Repo.transaction(fn ->
      incident = lock(id)

      with :ok <- check_not_author(incident, user),
           :ok <- check_open(incident),
           :ok <- check_near(incident, lat, lng, radius_m),
           token = Privacy.voter_token(user.id, incident.id),
           :ok <- check_not_voted(incident, token) do
        Repo.insert!(%Vote{incidente_id: incident.id, valor: valor, voter_token: token})
        apply_vote(incident, valor, threshold)
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  # --- Validaciones baratas, antes de tocar la base ---

  defp cast_valor(valor) when is_binary(valor) do
    case Map.fetch(@valores, valor) do
      {:ok, atom} -> {:ok, atom}
      :error -> {:error, :invalid_vote}
    end
  end

  defp cast_valor(_otro), do: {:error, :invalid_vote}

  # Solo números dentro del globo. Se convierten a float: PostGIS espera doble precisión.
  defp cast_location(lat, lng)
       when is_number(lat) and is_number(lng) and lat >= -90 and lat <= 90 and lng >= -180 and
              lng <= 180,
       do: {:ok, {lat * 1.0, lng * 1.0}}

  defp cast_location(_lat, _lng), do: {:error, :invalid_location}

  defp check_verified(%User{nivel: :verificado}), do: :ok
  defp check_verified(%User{}), do: {:error, :not_verified}

  # `Ecto.UUID.cast/1` acepta cualquier binario de 16 bytes como un UUID crudo:
  # el texto de un UUID mide exactamente 36 caracteres.
  defp cast_id(id) when is_binary(id) and byte_size(id) == 36 do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> {:ok, uuid}
      :error -> {:error, :not_found}
    end
  end

  defp cast_id(_otro), do: {:error, :not_found}

  # --- Dentro de la transacción ---

  defp lock(id) do
    case Repo.one(from i in Incident, where: i.id == ^id, lock: "FOR UPDATE") do
      %Incident{} = incident -> incident
      nil -> Repo.rollback(:not_found)
    end
  end

  # Se recalcula el código del autor y se compara en tiempo constante. Un reporte
  # sin autor (siembra de ejemplo) no es de nadie: cualquiera puede votarlo.
  defp check_not_author(%Incident{reporter_token: token, id: id}, %User{id: user_id})
       when is_binary(token) do
    if Privacy.same_token?(token, Privacy.reporter_token(user_id, id)),
      do: {:error, :own_report},
      else: :ok
  end

  defp check_not_author(_incident, _user), do: :ok

  defp check_open(%Incident{estado: :sin_verificar}), do: :ok
  defp check_open(_cerrado), do: {:error, :voting_closed}

  defp check_near(%Incident{id: id}, lat, lng, radius_m) do
    near? =
      Repo.exists?(
        from i in Incident,
          where:
            i.id == ^id and
              fragment(
                "ST_DWithin(?, ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography, ?)",
                i.ubicacion,
                ^lng,
                ^lat,
                ^(radius_m * 1.0)
              )
      )

    if near?, do: :ok, else: {:error, :too_far}
  end

  defp check_not_voted(%Incident{id: id}, token) do
    if Repo.exists?(from v in Vote, where: v.incidente_id == ^id and v.voter_token == ^token),
      do: {:error, :already_voted},
      else: :ok
  end

  defp apply_vote(%Incident{} = incident, valor, threshold) do
    confirmaciones = incident.confirmaciones + if(valor == :confirmo, do: 1, else: 0)
    falsos = incident.falsos + if(valor == :falso, do: 1, else: 0)

    estado =
      cond do
        confirmaciones >= threshold -> :verificado
        falsos >= threshold -> :descartado
        true -> :sin_verificar
      end

    incident
    |> Ecto.Changeset.change(confirmaciones: confirmaciones, falsos: falsos, estado: estado)
    |> Repo.update!()
  end

  defp config(key), do: :civic |> Application.fetch_env!(__MODULE__) |> Keyword.fetch!(key)
end
