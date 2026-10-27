defmodule CivicWeb.HealthControllerTest do
  use CivicWeb.ConnCase, async: true

  test "GET /health devuelve ok con la BD arriba", %{conn: conn} do
    conn = get(conn, ~p"/health")
    assert json_response(conn, 200) == %{"status" => "ok"}
  end
end
