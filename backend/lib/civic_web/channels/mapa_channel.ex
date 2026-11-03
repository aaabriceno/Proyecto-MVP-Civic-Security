defmodule CivicWeb.MapaChannel do
  @moduledoc """
  Canal en tiempo real del mapa. Solo el servidor emite eventos
  (`incidente_nuevo`); los clientes únicamente escuchan, de modo que nadie
  puede inyectar reportes falsos por el socket.

  Por ahora hay un solo tópico, `mapa:arequipa`. Más adelante se dividirá por
  celdas geohash.
  """

  use CivicWeb, :channel

  @topic "mapa:arequipa"

  @impl true
  def join(@topic, _payload, socket), do: {:ok, socket}
  def join(_otro_topico, _payload, _socket), do: {:error, %{reason: "unauthorized"}}

  # Los clientes solo escuchan: cualquier mensaje que envíen se ignora.
  # Sin esta cláusula, un evento desconocido haría caer el proceso del canal.
  @impl true
  def handle_in(_evento, _payload, socket), do: {:noreply, socket}
end
