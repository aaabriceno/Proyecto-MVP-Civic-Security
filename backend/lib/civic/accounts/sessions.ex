defmodule Civic.Accounts.Sessions do
  @moduledoc """
  Sesiones con dos tokens:

    * **access token** (15 min): firmado con `Phoenix.Token`, lleva solo el id
      de la cuenta. El servidor lo valida sin consultar la base.
    * **refresh token** (30 días): 32 bytes aleatorios. En la base solo queda su
      SHA-256. Es de un solo uso: cada vez que se usa entrega uno nuevo y queda
      marcado como usado. Si alguien presenta uno ya usado, hay una copia en
      circulación y se revoca toda la **familia** (todos los tokens nacidos del
      mismo inicio de sesión), salvo que sea un reintento de pocos segundos
      (ver `refresh/2`).

  La sesión vence a los 30 días del inicio de sesión (tope absoluto), la uses o
  no: rotar el token no alarga el plazo, el token nuevo hereda el vencimiento.
  Pasado ese día hay que escribir de nuevo alias y contraseña (ASVS 3.3.2, L1).
  Si no se usa, el mismo plazo la cierra, así que el tope por inactividad queda
  cubierto también.

  Las fechas de la tabla son días, sin hora, para que los tiempos de las
  sesiones no sirvan para sospechar quién hizo un reporte. El vencimiento vale
  hasta el final de su día.

  La opción `:now` existe solo para probar el paso del tiempo.
  """

  import Ecto.Query

  alias Civic.Accounts.{RefreshReplay, RefreshToken, User}
  alias Civic.Repo

  # Cambiar la sal (v1 -> v2) invalida todos los access tokens: sirve para rotar
  # la clave. Es una sal distinta de cualquier otro uso de la clave del servidor.
  @access_salt "civic access token v1"
  @access_ttl_seconds 900
  @refresh_ttl_days 30
  @refresh_bytes 32
  # 32 bytes en base64 seguro para URL, sin relleno
  @refresh_format ~r/\A[A-Za-z0-9_-]{43}\z/

  @type tokens :: %{
          access_token: String.t(),
          refresh_token: String.t(),
          expires_in: pos_integer()
        }

  @doc "Abre una sesión nueva (una familia nueva) para la cuenta."
  @spec issue(User.t(), keyword()) :: {:ok, tokens()}
  def issue(%User{id: user_id}, opts \\ []) do
    now = now(opts)
    expires_on = now |> DateTime.to_date() |> Date.add(@refresh_ttl_days)

    {:ok, new_pair(user_id, Ecto.UUID.generate(), now, expires_on)}
  end

  @doc """
  Valida un access token. Devuelve el id de la cuenta o `{:error, :invalid_token}`
  (firma mala, manipulado, vencido o de otro propósito: todos igual).
  """
  @spec verify_access(term()) :: {:ok, String.t()} | {:error, :invalid_token}
  def verify_access(token) when is_binary(token) do
    case Phoenix.Token.verify(secret(), @access_salt, token, max_age: @access_ttl_seconds) do
      {:ok, id} when is_binary(id) -> {:ok, id}
      _ -> {:error, :invalid_token}
    end
  end

  def verify_access(_), do: {:error, :invalid_token}

  @doc """
  Cambia un refresh token por un par nuevo. El token presentado queda usado.

  Falla con `{:error, :invalid_token}` si no existe, venció o ya se había usado
  (en este último caso además se revoca la familia). El error es siempre el
  mismo para no decirle a quien prueba tokens por qué falló.

  **Excepción: repetir.** Si el token se usó hace menos de la ventana de
  `Civic.Accounts.RefreshReplay` (30 s) y el token nuevo que produjo sigue sin
  usarse, se devuelve ese mismo token nuevo (con un access token fresco) en vez
  de revocar. Cubre el caso en que la respuesta se perdió y el teléfono reintenta.
  """
  @spec refresh(term(), keyword()) :: {:ok, tokens()} | {:error, :invalid_token}
  def refresh(token, opts \\ [])

  def refresh(token, opts) when is_binary(token) do
    now = now(opts)
    today = DateTime.to_date(now)

    if Regex.match?(@refresh_format, token) do
      # La transacción devuelve el resultado; no se usa rollback porque la
      # revocación por reuso tiene que quedar guardada aunque la respuesta sea un error
      {:ok, result} = Repo.transaction(fn -> rotate(find_locked(token), today, now) end)
      result
    else
      {:error, :invalid_token}
    end
  end

  def refresh(_token, _opts), do: {:error, :invalid_token}

  @doc """
  Cierra la sesión: revoca toda la familia del refresh token. Siempre devuelve
  `:ok`, exista o no el token, para no revelar nada.
  """
  @spec revoke(term(), keyword()) :: :ok
  def revoke(token, opts \\ [])

  def revoke(token, opts) when is_binary(token) do
    if Regex.match?(@refresh_format, token) do
      familia =
        Repo.one(from t in RefreshToken, where: t.token_hash == ^hash(token), select: t.familia)

      if familia, do: revoke_family(familia, DateTime.to_date(now(opts)))
    end

    :ok
  end

  def revoke(_token, _opts), do: :ok

  # --- rotación ---

  defp rotate(nil, _today, _now), do: {:error, :invalid_token}

  # Ya usado o revocado. Si hace segundos que se cambió, lo más probable es que la
  # respuesta se perdiera y sea un reintento honesto: se repite el mismo resultado.
  # Si no, otra persona tiene una copia y se cae toda la familia.
  defp rotate(%RefreshToken{revocado_en: revocado} = row, today, now)
       when not is_nil(revocado) do
    case replay(row, today, now) do
      {:ok, pair} ->
        {:ok, pair}

      :none ->
        revoke_family(row.familia, today)
        {:error, :invalid_token}
    end
  end

  defp rotate(%RefreshToken{} = row, today, now) do
    if Date.compare(today, row.expira_en) == :gt do
      {:error, :invalid_token}
    else
      row |> Ecto.Changeset.change(revocado_en: today) |> Repo.update!()
      # El token nuevo hereda el vencimiento: rotar no alarga la sesión
      pair = new_pair(row.usuario_id, row.familia, now, row.expira_en)

      # Se recuerda DENTRO de la transacción, mientras la fila sigue bloqueada: si
      # se hiciera después, un reintento simultáneo podría entrar entre la
      # confirmación y el recuerdo, no encontrar nada y cerrar la sesión.
      RefreshReplay.remember(row.token_hash, pair.refresh_token, to_ms(now))
      {:ok, pair}
    end
  end

  # El resultado de rotar `row` hace pocos segundos, si todavía se puede repetir.
  # Cualquier duda cae hacia el lado estricto: `:none` revoca la familia.
  defp replay(row, today, now) do
    with false <- Date.compare(today, row.expira_en) == :gt,
         {:ok, next} <- RefreshReplay.lookup(row.token_hash, to_ms(now)),
         true <- unused?(next) do
      {:ok,
       %{
         access_token: sign_access(row.usuario_id, now),
         refresh_token: next,
         expires_in: @access_ttl_seconds
       }}
    else
      _ -> :none
    end
  end

  # Entregar un token que ya se gastó (o que se cerró con la sesión) sería dejarle
  # al teléfono uno muerto: en ese caso no es un reintento sino un reuso real.
  defp unused?(refresh_token) do
    Repo.exists?(
      from t in RefreshToken,
        where: t.token_hash == ^hash(refresh_token) and is_nil(t.revocado_en)
    )
  end

  # Con la fila bloqueada (FOR UPDATE), dos refresh simultáneos con el mismo
  # token no pasan los dos: el segundo ve el token ya usado.
  defp find_locked(token) do
    Repo.one(from t in RefreshToken, where: t.token_hash == ^hash(token), lock: "FOR UPDATE")
  end

  defp revoke_family(familia, today) do
    Repo.update_all(
      from(t in RefreshToken, where: t.familia == ^familia and is_nil(t.revocado_en)),
      set: [revocado_en: today]
    )
  end

  # --- creación de tokens ---

  defp new_pair(user_id, familia, now, expires_on) do
    refresh = Base.url_encode64(:crypto.strong_rand_bytes(@refresh_bytes), padding: false)

    Repo.insert!(%RefreshToken{
      usuario_id: user_id,
      token_hash: hash(refresh),
      familia: familia,
      creado_en: DateTime.to_date(now),
      expira_en: expires_on
    })

    %{
      access_token: sign_access(user_id, now),
      refresh_token: refresh,
      expires_in: @access_ttl_seconds
    }
  end

  defp sign_access(user_id, now),
    do: Phoenix.Token.sign(secret(), @access_salt, user_id, signed_at: DateTime.to_unix(now))

  defp to_ms(now), do: DateTime.to_unix(now, :millisecond)

  # SHA-256 basta porque el token es aleatorio de 256 bits y no se puede adivinar
  # (a diferencia de una contraseña, que necesita un hash lento como Argon2id)
  defp hash(token), do: :crypto.hash(:sha256, token)

  defp secret, do: Application.fetch_env!(:civic, CivicWeb.Endpoint)[:secret_key_base]

  defp now(opts), do: Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)
end
