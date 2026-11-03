defmodule CivicWeb.SecurityTest do
  use CivicWeb.ConnCase, async: true

  @headers ~w(x-content-type-options x-frame-options referrer-policy content-security-policy cache-control)

  defp json_post(conn, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> put_req_header("idempotency-key", Ecto.UUID.generate())
    |> post(~p"/v1/incidents", body)
  end

  test "las respuestas llevan cabeceras de seguridad", %{conn: conn} do
    conn = get(conn, ~p"/health")

    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
    assert get_resp_header(conn, "x-frame-options") == ["DENY"]
    assert get_resp_header(conn, "referrer-policy") == ["no-referrer"]
    assert get_resp_header(conn, "cache-control") == ["no-store"]

    assert get_resp_header(conn, "content-security-policy") ==
             ["default-src 'none'; frame-ancestors 'none'"]
  end

  test "las respuestas de error también llevan cabeceras de seguridad", %{conn: conn} do
    conn = get(conn, "/no-existe")
    assert conn.status == 404

    for h <- @headers do
      assert get_resp_header(conn, h) != [], "falta #{h} en la respuesta 404"
    end
  end

  test "413 si el cuerpo supera el límite", %{conn: conn} do
    body = Jason.encode!(%{"descripcion" => String.duplicate("a", 20_000)})
    assert_error_sent 413, fn -> json_post(conn, body) end
  end

  test "415 si el cuerpo no es JSON (formularios urlencoded)", %{conn: conn} do
    assert_error_sent 415, fn ->
      conn
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> put_req_header("idempotency-key", Ecto.UUID.generate())
      |> post(~p"/v1/incidents", "tipo=robo&lat=-16.39&lng=-71.53")
    end
  end

  test "415 si el cuerpo es multipart (sin archivos temporales en disco)", %{conn: conn} do
    boundary = "xyz"

    body =
      "--#{boundary}\r\ncontent-disposition: form-data; name=\"tipo\"\r\n\r\nrobo\r\n--#{boundary}--\r\n"

    assert_error_sent 415, fn ->
      conn
      |> put_req_header("content-type", "multipart/form-data; boundary=#{boundary}")
      |> put_req_header("idempotency-key", Ecto.UUID.generate())
      |> post(~p"/v1/incidents", body)
    end
  end

  test "no se emiten cookies de sesión", %{conn: conn} do
    conn = get(conn, ~p"/health")
    assert get_resp_header(conn, "set-cookie") == []
  end
end
