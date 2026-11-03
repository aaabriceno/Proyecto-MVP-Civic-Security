defmodule CivicWeb.Plugs.RateLimit do
  @moduledoc """
  Limita las solicitudes por cliente. Uso en el router:

      plug CivicWeb.Plugs.RateLimit, bucket: :write
  """

  import Plug.Conn

  alias Civic.RateLimit
  alias CivicWeb.ClientIP

  def init(opts), do: Keyword.fetch!(opts, :bucket)

  def call(conn, bucket) do
    case RateLimit.check(bucket, ClientIP.get(conn)) do
      :ok -> conn
      {:deny, retry_ms} -> deny(conn, retry_ms)
    end
  end

  defp deny(conn, retry_ms) do
    retry_s = max(div(retry_ms, 1000) + 1, 1)

    conn
    |> put_resp_header("retry-after", Integer.to_string(retry_s))
    |> put_resp_content_type("application/json")
    |> send_resp(
      429,
      Jason.encode!(%{
        error: %{
          code: "rate_limited",
          message: "Demasiadas solicitudes. Intenta de nuevo en #{retry_s} s."
        }
      })
    )
    |> halt()
  end
end
