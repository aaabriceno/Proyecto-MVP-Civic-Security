defmodule Civic.Incidents do
  @moduledoc """
  Contexto de incidentes: crear y consultar reportes anónimos.
  """

  import Ecto.Query

  alias Civic.Accounts.User
  alias Civic.Incidents.Incident
  alias Civic.Incidents.Quota
  alias Civic.Privacy
  alias Civic.Repo

  @max_resultados 500

  @doc """
  Crea un incidente SIN cuenta (siembra de desarrollo y pruebas): no guarda autor
  ni gasta cupo. El servidor nunca lo usa para atender a un usuario: ver
  `report_incident/3`.
  """
  def create_incident(attrs, idempotency_key), do: crear(nil, attrs, idempotency_key)

  @doc """
  Crea un incidente reportado por `user`.

  `idempotency_key` evita duplicados cuando la app reintenta el envío:

    * clave nueva -> `{:ok, :created, incidente}`
    * clave repetida con el **mismo** contenido y la **misma** cuenta ->
      `{:ok, :existing, incidente}` (no gasta cupo)
    * clave repetida con **otro** contenido, o de **otra** cuenta ->
      `{:error, :idempotency_conflict}` (si no, el reporte nuevo se perdería en
      silencio, o una cuenta recibiría el incidente de otra)
    * cupo diario agotado -> `{:error, {:quota_exceeded, ms_para_reintentar}}`

  Del autor solo se guarda `HMAC(k_rep, cuenta ‖ incidente)`: distinto en cada
  incidente, así que no se pueden enlazar los reportes de una misma persona, y la
  base de datos no tiene ninguna columna con el id de la cuenta.
  """
  def report_incident(%User{} = user, attrs, idempotency_key),
    do: crear(user, attrs, idempotency_key)

  defp crear(author, attrs, idempotency_key) do
    case Repo.get_by(Incident, idempotency_key: idempotency_key) do
      %Incident{} = existente -> replay(existente, attrs, author)
      nil -> insertar(attrs, idempotency_key, author)
    end
  end

  defp replay(existente, attrs, author) do
    changeset = Incident.create_changeset(%Incident{}, attrs)

    cond do
      not changeset.valid? -> {:error, %{changeset | action: :insert}}
      not mismo_autor?(existente, author) -> {:error, :idempotency_conflict}
      Incident.same_content?(existente, changeset) -> {:ok, :existing, existente}
      true -> {:error, :idempotency_conflict}
    end
  end

  # Sin autor (siembra y pruebas) no hay nada que comparar. Con autor, el token
  # guardado debe ser el de ESTA cuenta para ESTE incidente; un incidente sin
  # token (siembra) no se puede reclamar con una cuenta.
  defp mismo_autor?(_existente, nil), do: true

  defp mismo_autor?(%Incident{reporter_token: token, id: id}, %User{id: user_id})
       when is_binary(token),
       do: Privacy.same_token?(token, Privacy.reporter_token(user_id, id))

  defp mismo_autor?(_existente, _user), do: false

  @doc """
  Incidentes creados después de `since` que caen dentro del `bbox`
  (`{min_lng, min_lat, max_lng, max_lat}`), del más nuevo al más antiguo.
  Devuelve como máximo 500.
  """
  def list_recent({min_lng, min_lat, max_lng, max_lat}, %DateTime{} = since) do
    Incident
    |> where([i], i.inserted_at > ^since)
    |> where(
      [i],
      fragment(
        "ST_Intersects(?, ST_MakeEnvelope(?, ?, ?, ?, 4326)::geography)",
        i.ubicacion,
        ^min_lng,
        ^min_lat,
        ^max_lng,
        ^max_lat
      )
    )
    |> order_by([i], desc: i.inserted_at)
    |> limit(^@max_resultados)
    |> Repo.all()
  end

  # Un reporte inválido no gasta cupo: primero se valida y solo entonces se cobra.
  defp insertar(attrs, idempotency_key, author) do
    changeset = Incident.create_changeset(nuevo(idempotency_key, author), attrs)

    with :ok <- validar(changeset),
         :ok <- cobrar_cupo(author) do
      case Repo.insert(changeset) do
        {:ok, incident} -> {:ok, :created, incident}
        {:error, changeset} -> manejar_error(changeset, attrs, idempotency_key, author)
      end
    end
  end

  # El id se genera antes de insertar porque el token del autor depende de él
  defp nuevo(idempotency_key, nil), do: %Incident{idempotency_key: idempotency_key}

  defp nuevo(idempotency_key, %User{id: user_id}) do
    id = Ecto.UUID.generate()

    %Incident{
      id: id,
      idempotency_key: idempotency_key,
      reporter_token: Privacy.reporter_token(user_id, id)
    }
  end

  defp validar(%Ecto.Changeset{valid?: true}), do: :ok
  defp validar(changeset), do: {:error, %{changeset | action: :insert}}

  defp cobrar_cupo(nil), do: :ok
  defp cobrar_cupo(%User{} = user), do: Quota.consume(user)

  # Si otra petición con la misma key ganó la carrera, se trata como repetición
  defp manejar_error(changeset, attrs, idempotency_key, author) do
    if Keyword.has_key?(changeset.errors, :idempotency_key) do
      replay(Repo.get_by!(Incident, idempotency_key: idempotency_key), attrs, author)
    else
      {:error, changeset}
    end
  end
end
