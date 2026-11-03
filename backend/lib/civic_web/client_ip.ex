defmodule CivicWeb.ClientIP do
  @moduledoc """
  Identifica al cliente **solo** para limitar la tasa de solicitudes. El
  resultado se usa como clave en memoria; nunca se guarda ni se registra.

  Por defecto es la dirección del socket TCP. Una cabecera como
  `x-forwarded-for` la puede escribir cualquier cliente, así que solo se
  obedece si se configura `:client_ip_header` (variable `CLIENT_IP_HEADER`),
  y únicamente debe hacerse cuando la API está detrás de un proxy que
  sobrescribe esa cabecera.
  """

  def get(%Plug.Conn{} = conn) do
    case trusted_header() do
      nil -> format(conn.remote_ip)
      header -> conn |> Plug.Conn.get_req_header(header) |> first_value(conn.remote_ip)
    end
  end

  @doc "Igual que `get/1` para el `connect_info` de un socket."
  def from_connect_info(info) do
    peer = get_in(info, [:peer_data, :address])

    case trusted_header() do
      nil -> format(peer)
      header -> info |> Map.get(:x_headers, []) |> List.keyfind(header, 0) |> header_value(peer)
    end
  end

  defp trusted_header do
    case Application.get_env(:civic, :client_ip_header) do
      header when is_binary(header) and header != "" -> String.downcase(header)
      _ -> nil
    end
  end

  defp first_value([value | _], _fallback), do: clean(value)
  defp first_value([], fallback), do: format(fallback)

  defp header_value({_name, value}, _fallback), do: clean(value)
  defp header_value(nil, fallback), do: format(fallback)

  # "ip1, ip2": la primera es el cliente; se recorta para acotar la clave
  defp clean(value),
    do: value |> String.split(",") |> hd() |> String.trim() |> String.slice(0, 64)

  defp format(ip) when is_tuple(ip), do: ip |> :inet.ntoa() |> to_string()
  defp format(_), do: "desconocida"
end
