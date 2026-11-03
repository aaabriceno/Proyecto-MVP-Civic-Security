defmodule CivicWeb.MapaChannelTest do
  use CivicWeb.ChannelCase

  alias CivicWeb.{MapaChannel, UserSocket}

  defp join_socket(topic) do
    UserSocket
    |> socket("anonimo", %{})
    |> subscribe_and_join(MapaChannel, topic)
  end

  test "se puede unir al tópico mapa:arequipa" do
    assert {:ok, _reply, _socket} = join_socket("mapa:arequipa")
  end

  test "rechaza cualquier otro tópico" do
    assert {:error, %{reason: "unauthorized"}} = join_socket("mapa:lima")
    assert {:error, %{reason: "unauthorized"}} = join_socket("mapa:lobby")
  end

  test "el servidor emite incidente_nuevo a los suscritos" do
    {:ok, _, _socket} = join_socket("mapa:arequipa")

    CivicWeb.Endpoint.broadcast!("mapa:arequipa", "incidente_nuevo", %{id: "x"})
    assert_push "incidente_nuevo", %{id: "x"}
  end

  test "los clientes no pueden enviar mensajes al canal" do
    {:ok, _, socket} = join_socket("mapa:arequipa")

    ref = push(socket, "shout", %{"falso" => "reporte"})
    refute_reply ref, :ok
    refute_broadcast "shout", _
  end
end
