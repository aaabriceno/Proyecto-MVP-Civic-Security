defmodule CivicWeb.UserSocket do
  @moduledoc """
  Socket público de solo lectura del mapa. Sin autenticación en el esqueleto:
  los reportes del mapa son públicos y el socket no guarda ninguna identidad
  (`id/1` devuelve `nil`, es decir, un socket anónimo).
  """

  use Phoenix.Socket

  channel "mapa:*", CivicWeb.MapaChannel

  @impl true
  def connect(_params, socket, _connect_info), do: {:ok, socket}

  @impl true
  def id(_socket), do: nil
end
