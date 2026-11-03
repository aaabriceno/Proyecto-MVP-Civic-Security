defmodule CivicWeb.UserSocket do
  @moduledoc """
  Socket público de solo lectura del mapa. Sin autenticación en el esqueleto:
  los reportes del mapa son públicos y el socket no guarda ninguna identidad
  (`id/1` devuelve `nil`, es decir, un socket anónimo).
  """

  use Phoenix.Socket

  channel "mapa:*", CivicWeb.MapaChannel

  # Limita cuántas conexiones por minuto puede abrir cada cliente
  @impl true
  def connect(_params, socket, connect_info) do
    case Civic.RateLimit.check(:socket, CivicWeb.ClientIP.from_connect_info(connect_info)) do
      :ok -> {:ok, socket}
      {:deny, _retry_ms} -> :error
    end
  end

  @impl true
  def id(_socket), do: nil
end
