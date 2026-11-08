defmodule Civic.Privacy do
  @moduledoc """
  Todo lo que convierte datos sensibles en etiquetas irreversibles.

  Usamos **HMAC-SHA256 con una clave secreta**. Una función HMAC es de un solo
  sentido: de la etiqueta no se puede volver al dato. A diferencia de un SHA-256
  simple, sin la clave nadie puede ni siquiera *probar* candidatos (un DNI tiene
  solo 10^8 posibilidades: SHA-256 sin clave se revierte en segundos).

  Hay tres claves independientes, una por propósito, para que la filtración de
  una no abra las otras:

    * `:verif` – DNI -> `verif_hash` (una persona = una cuenta).
    * `:rep`   – (cuenta, incidente) -> token del **autor** del reporte.
    * `:vote`  – (cuenta, incidente) -> token del **votante**.

  Los tokens son *por incidente*: la misma cuenta produce una etiqueta distinta
  en cada incidente, así que nadie sin las claves puede unir los reportes o los
  votos de una persona. Las claves viven en variables de entorno (ver
  `config/runtime.exs`), nunca en la base de datos ni en el repositorio, y están
  *versionadas* para poder rotarlas.

  **Esto es seudonimización fuerte, no anonimato absoluto**: quien tenga a la
  vez la base de datos y las claves podría reidentificar. Por eso las claves se
  separan de la base y entre sí (ver docs/arquitectura-mvp.md, sección 7).
  """

  @min_key_bytes 32
  @purposes [:verif, :rep, :vote]

  # La etiqueta va dentro del mensaje (además de usar claves distintas) para que
  # un valor calculado para un propósito nunca sirva para otro.
  @dni_label "civic/dni/v1\0"
  @reporter_label "civic/reporter/v1\0"
  @voter_label "civic/voter/v1\0"

  @type hash :: <<_::256>>

  @doc """
  HMAC del DNI para guardarlo en `verif_hash`. Devuelve también la versión de
  la clave usada (hay que guardarla junto al hash para poder rotar claves).

  Solo acepta exactamente 8 dígitos ASCII (se ignoran los espacios de los
  extremos). Un entero no se acepta: perdería los ceros a la izquierda.
  """
  @spec dni_hash(term(), keyword()) ::
          {:ok, %{hash: hash(), version: pos_integer()}} | {:error, :invalid_dni}
  def dni_hash(dni, opts \\ []) do
    with {:ok, dni} <- normalize_dni(dni) do
      version = version(:verif, opts)
      {:ok, %{hash: mac(:verif, version, @dni_label <> dni), version: version}}
    end
  end

  @doc "Token del autor de un reporte: `HMAC(k_rep, cuenta ‖ incidente)`."
  @spec reporter_token(String.t(), String.t(), keyword()) :: hash()
  def reporter_token(account_id, incident_id, opts \\ []),
    do: token(:rep, @reporter_label, account_id, incident_id, opts)

  @doc "Token de un votante en un incidente: `HMAC(k_vote, cuenta ‖ incidente)`."
  @spec voter_token(String.t(), String.t(), keyword()) :: hash()
  def voter_token(account_id, incident_id, opts \\ []),
    do: token(:vote, @voter_label, account_id, incident_id, opts)

  @doc "Compara dos tokens en tiempo constante (no revela cuántos bytes coinciden)."
  @spec same_token?(term(), term()) :: boolean()
  def same_token?(a, b) when is_binary(a) and is_binary(b) and byte_size(a) == byte_size(b),
    do: Plug.Crypto.secure_compare(a, b)

  def same_token?(_a, _b), do: false

  @doc """
  Comprueba la configuración de claves. Se llama al arrancar para que la
  aplicación **no inicie** con claves ausentes, cortas o repetidas.
  """
  @spec validate_config!() :: :ok
  def validate_config! do
    config = config()
    keys = Keyword.fetch!(config, :keys)
    current = Keyword.fetch!(config, :current)

    for purpose <- @purposes do
      version = Map.fetch!(current, purpose)

      unless Map.has_key?(keys, {purpose, version}) do
        raise ArgumentError,
              "falta la clave de #{purpose} v#{version} (versión actual de #{purpose})"
      end
    end

    for {{purpose, version}, key} <- keys do
      unless is_binary(key) and byte_size(key) >= @min_key_bytes do
        raise ArgumentError,
              "la clave de #{purpose} v#{version} debe tener al menos #{@min_key_bytes} bytes"
      end
    end

    case Enum.find(duplicate_keys(keys), & &1) do
      nil ->
        :ok

      {a, b} ->
        raise ArgumentError,
              "las claves deben ser independientes: #{inspect(a)} repite a #{inspect(b)}"
    end
  end

  # --- Internas ---

  defp token(purpose, label, account_id, incident_id, opts) do
    version = version(purpose, opts)
    message = label <> uuid!(account_id) <> ":" <> uuid!(incident_id)
    mac(purpose, version, message)
  end

  defp normalize_dni(dni) when is_binary(dni) do
    trimmed = String.trim(dni)
    if Regex.match?(~r/\A[0-9]{8}\z/, trimmed), do: {:ok, trimmed}, else: {:error, :invalid_dni}
  end

  defp normalize_dni(_other), do: {:error, :invalid_dni}

  # Forma canónica (minúsculas) para que el mismo UUID dé siempre la misma etiqueta
  defp uuid!(value) when is_binary(value) do
    case Ecto.UUID.cast(value) do
      {:ok, uuid} -> uuid
      :error -> raise ArgumentError, "se esperaba un UUID, se recibió #{inspect(value)}"
    end
  end

  defp uuid!(value), do: raise(ArgumentError, "se esperaba un UUID, se recibió #{inspect(value)}")

  defp mac(purpose, version, message),
    do: :crypto.mac(:hmac, :sha256, key!(purpose, version), message)

  defp key!(purpose, version) do
    case config()[:keys][{purpose, version}] do
      nil -> raise ArgumentError, "no hay clave configurada para #{purpose} v#{version}"
      key -> key
    end
  end

  defp version(purpose, opts),
    do: Keyword.get_lazy(opts, :version, fn -> config()[:current][purpose] end)

  defp config, do: Application.fetch_env!(:civic, __MODULE__)

  # Pares de claves idénticas; `nil` donde no hay repetición
  defp duplicate_keys(keys) do
    entries = Enum.sort(keys)

    for {{id, key}, index} <- Enum.with_index(entries),
        {other_id, other_key} <- Enum.take(entries, index) do
      if key == other_key, do: {id, other_id}
    end
  end
end
