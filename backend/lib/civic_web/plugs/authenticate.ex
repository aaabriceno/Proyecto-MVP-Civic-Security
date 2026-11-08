defmodule CivicWeb.Plugs.Authenticate do
  @moduledoc """
  Exige un access token válido en `Authorization: Bearer <token>`.

  Si es válido deja el id de la cuenta en `conn.assigns.current_user_id`. Si no,
  responde 401 y corta la petición. El motivo (falta, mal formado, vencido,
  manipulado) nunca se dice: la respuesta es siempre la misma.

  Solo valida la firma y la vigencia del token; no consulta la base. Las rutas
  que necesiten la cuenta la cargan ellas (y deben tratar la ausencia como 401).

      plug CivicWeb.Plugs.Authenticate
  """

  import Plug.Conn

  alias Civic.Accounts.Sessions

  # El esquema no distingue mayúsculas (RFC 7235); el token no lleva espacios
  @bearer ~r/\ABearer +(\S+)\z/i

  def init(opts), do: opts

  def call(conn, _opts) do
    with [header | _] <- get_req_header(conn, "authorization"),
         [_, token] <- Regex.run(@bearer, header),
         {:ok, user_id} <- Sessions.verify_access(token) do
      assign(conn, :current_user_id, user_id)
    else
      _ -> conn |> deny() |> halt()
    end
  end

  @doc "La respuesta 401 uniforme. También la usan los controladores."
  def deny(conn) do
    conn
    |> put_resp_header("www-authenticate", "Bearer")
    |> put_resp_content_type("application/json")
    |> send_resp(
      401,
      Jason.encode!(%{error: %{code: "unauthorized", message: "Necesitas iniciar sesión"}})
    )
  end
end
