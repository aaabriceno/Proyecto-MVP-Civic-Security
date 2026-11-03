defmodule CivicWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :civic

  # Los clientes solo escuchan y envían latidos: un marco de 4 KB sobra, y así
  # nadie puede mandar mensajes enormes por el socket.
  socket "/socket", CivicWeb.UserSocket,
    websocket: [
      max_frame_size: 4_096,
      compress: false,
      timeout: 60_000,
      connect_info: [:peer_data, :x_headers]
    ],
    longpoll: false

  # API pura: sin sesiones, cookies ni archivos estáticos (menos superficie de
  # ataque). La app móvil no usa nada de eso.
  plug :put_security_headers

  if code_reloading? do
    plug Phoenix.CodeReloader
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :civic
  end

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  # Solo JSON y cuerpos de hasta 8 KB (un reporte pesa menos de 3 KB). Otros
  # tipos, como formularios o multipart (que escribe archivos temporales),
  # responden 415.
  plug Plug.Parsers,
    parsers: [:json],
    length: 8_192,
    json_decoder: Phoenix.json_library()

  plug Plug.Head
  plug CivicWeb.Router

  defp put_security_headers(conn, _opts) do
    Plug.Conn.merge_resp_headers(conn, [
      {"x-content-type-options", "nosniff"},
      {"x-frame-options", "DENY"},
      {"referrer-policy", "no-referrer"},
      {"content-security-policy", "default-src 'none'; frame-ancestors 'none'"},
      # Los reportes cambian en tiempo real: que nada se guarde en cachés
      {"cache-control", "no-store"}
    ])
  end
end
