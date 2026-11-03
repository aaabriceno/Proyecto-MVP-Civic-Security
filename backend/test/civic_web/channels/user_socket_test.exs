defmodule CivicWeb.UserSocketTest do
  # Modifica la configuración global: no puede correr en paralelo
  use CivicWeb.ChannelCase, async: false

  alias CivicWeb.UserSocket

  setup do
    original = Application.fetch_env!(:civic, CivicWeb.RateLimit)
    Application.put_env(:civic, CivicWeb.RateLimit, Keyword.put(original, :socket, {2, 60_000}))
    on_exit(fn -> Application.put_env(:civic, CivicWeb.RateLimit, original) end)
    :ok
  end

  defp connect_from(ip) do
    info = %{peer_data: %{address: ip, port: 40_000, ssl_cert: nil}, x_headers: []}
    connect(UserSocket, %{}, connect_info: info)
  end

  test "limita las conexiones por IP" do
    n = :erlang.unique_integer([:positive])
    ip = {10, 2, rem(n, 250) + 1, rem(div(n, 250), 250) + 1}

    assert {:ok, _} = connect_from(ip)
    assert {:ok, _} = connect_from(ip)
    assert :error = connect_from(ip)

    # Otra IP no se ve afectada
    assert {:ok, _} = connect_from({10, 3, 3, 3})
  end
end
