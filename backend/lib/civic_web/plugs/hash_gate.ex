defmodule CivicWeb.Plugs.HashGate do
  @moduledoc """
  Toma un cupo de `Civic.HashGate` mientras se atiende la petición, y lo devuelve
  al enviar la respuesta. Si no hay cupo, responde 503 con `retry-after` y corta.

  Va en las rutas que calculan Argon2id (registro e inicio de sesión), después
  del límite por IP para que lo rechazado por IP no gaste cupo.

      plug CivicWeb.Plugs.HashGate
  """

  import Plug.Conn

  alias Civic.HashGate

  def init(opts), do: opts

  def call(conn, _opts) do
    case HashGate.acquire() do
      :ok ->
        # Se ejecuta en este mismo proceso justo antes de enviar la respuesta. Si
        # la petición falla antes, el semáforo recupera el cupo cuando el proceso muere.
        register_before_send(conn, fn conn ->
          HashGate.release()
          conn
        end)

      :busy ->
        conn
        |> put_resp_header("retry-after", "1")
        |> put_resp_content_type("application/json")
        |> send_resp(
          503,
          Jason.encode!(%{
            error: %{
              code: "server_busy",
              message: "El servidor está ocupado. Intenta de nuevo en unos segundos."
            }
          })
        )
        |> halt()
    end
  end
end
