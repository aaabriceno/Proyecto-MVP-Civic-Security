defmodule Civic.Accounts do
  @moduledoc """
  Cuentas: registro e inicio de sesión con alias y contraseña.

  Esta capa solo conoce cuentas. Las sesiones (tokens) y los endpoints HTTP
  vienen después y usan estas funciones.
  """

  import Ecto.Query

  alias Civic.Accounts.{Consent, Password, User}
  alias Civic.Repo

  # Versión del texto de la política de privacidad que se acepta al registrarse.
  # Si el texto cambia, se sube la versión para volver a pedir el consentimiento.
  @consent_version "2026-11-v1"

  # Fuerza bruta: del 5.º fallo seguido en adelante la cuenta se bloquea 60 s,
  # y cada fallo posterior duplica la espera hasta 15 min. Es un retardo, no un
  # bloqueo permanente, para que un atacante no pueda dejar fuera a nadie.
  @fallos_sin_bloqueo 4
  @bloqueo_base_segundos 60
  @bloqueo_maximo_segundos 900
  # Los fallos de hace más de 1 hora no cuentan
  @memoria_de_fallos_segundos 3600

  def consent_version, do: @consent_version

  @doc """
  Crea una cuenta (nivel `:invitado`: aún no verificó su DNI) y guarda el
  consentimiento, todo en una sola transacción.

  `attrs` acepta `"alias"`, `"password"` y `"acepta_consentimiento"`.
  """
  @spec register(map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def register(attrs) do
    changeset = User.registration_changeset(%User{}, attrs)

    Ecto.Multi.new()
    |> Ecto.Multi.insert(:user, changeset)
    |> Ecto.Multi.insert(:consent, fn %{user: user} ->
      %Consent{usuario_id: user.id, version: @consent_version, aceptado_en: DateTime.utc_now()}
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, :user, changeset, _changes} -> {:error, changeset}
    end
  end

  @doc """
  Verifica alias y contraseña.

  Devuelve `{:ok, user}`, `{:error, :invalid_credentials}` o
  `{:error, {:locked, segundos}}` si la cuenta está bloqueada.

  El error es **el mismo** para un alias que no existe y para una contraseña
  equivocada, y tarda lo mismo, para no revelar qué alias existen. La opción
  `:now` existe solo para probar el bloqueo sin esperar.
  """
  @spec authenticate(term(), term(), keyword()) ::
          {:ok, User.t()} | {:error, :invalid_credentials | {:locked, pos_integer()}}
  def authenticate(alias_, password, opts \\ []) do
    now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)

    with true <- is_binary(password),
         %User{password_hash: hash} = user when is_binary(hash) <- get_by_alias(alias_) do
      check_credentials(user, password, now)
    else
      _ ->
        Password.no_user_verify()
        {:error, :invalid_credentials}
    end
  end

  defp get_by_alias(alias_) do
    alias_ = if is_binary(alias_), do: String.trim(alias_)

    # Si no tiene forma de alias no puede existir: no se consulta la base con basura
    if User.alias_valid?(alias_) do
      lowered = String.downcase(alias_)
      Repo.one(from u in User, where: fragment("lower(?)", u.alias) == ^lowered)
    end
  end

  defp check_credentials(user, password, now) do
    cond do
      (seconds = locked_seconds(user, now)) > 0 ->
        # Ni se mira la contraseña: durante el bloqueo no hay nada que adivinar
        {:error, {:locked, seconds}}

      Password.valid?(password, user.password_hash) ->
        {:ok, clear_failures(user)}

      true ->
        register_failure(user, now)
        {:error, :invalid_credentials}
    end
  end

  # Segundos que faltan para el fin del bloqueo (0 si no está bloqueada)
  defp locked_seconds(%User{bloqueado_hasta: nil}, _now), do: 0

  defp locked_seconds(%User{bloqueado_hasta: until}, now) do
    case DateTime.diff(until, now, :millisecond) do
      ms when ms > 0 -> div(ms + 999, 1000)
      _ -> 0
    end
  end

  defp clear_failures(%User{intentos_fallidos: 0, bloqueado_hasta: nil} = user), do: user

  defp clear_failures(user) do
    user
    |> Ecto.Changeset.change(intentos_fallidos: 0, ultimo_fallo_en: nil, bloqueado_hasta: nil)
    |> Repo.update!()
  end

  # Con la fila bloqueada (FOR UPDATE), dos intentos simultáneos no se pisan el
  # contador: si no, un atacante podría dar muchos intentos a la vez.
  defp register_failure(user, now) do
    Repo.transaction(fn ->
      current = Repo.one!(from u in User, where: u.id == ^user.id, lock: "FOR UPDATE")

      count = if stale?(current, now), do: 1, else: current.intentos_fallidos + 1

      current
      |> Ecto.Changeset.change(
        intentos_fallidos: count,
        ultimo_fallo_en: now,
        bloqueado_hasta: lock_until(count, now)
      )
      |> Repo.update!()
    end)
  end

  defp stale?(%User{ultimo_fallo_en: nil}, _now), do: false

  defp stale?(%User{ultimo_fallo_en: last}, now),
    do: DateTime.diff(now, last) > @memoria_de_fallos_segundos

  defp lock_until(count, _now) when count <= @fallos_sin_bloqueo, do: nil

  defp lock_until(count, now) do
    seconds =
      min(
        @bloqueo_base_segundos * Integer.pow(2, min(count - @fallos_sin_bloqueo - 1, 10)),
        @bloqueo_maximo_segundos
      )

    DateTime.add(now, seconds)
  end
end
