defmodule CivicWeb.MapControllerTest do
  use CivicWeb.ConnCase, async: true

  import Ecto.Query

  alias Civic.Incidents

  @bbox "-71.54,-16.40,-71.53,-16.39"

  defp create(lat, lng) do
    attrs = %{"tipo" => "robo", "lat" => lat, "lng" => lng}
    {:ok, :created, incident} = Incidents.create_incident(attrs, Ecto.UUID.generate())
    incident
  end

  test "200 con los incidentes dentro del bbox", %{conn: conn} do
    dentro = create(-16.395, -71.535)
    _fuera = create(-16.45, -71.60)

    conn = get(conn, ~p"/v1/map/snapshot?bbox=#{@bbox}")
    assert %{"data" => %{"incidentes" => [incidente]}} = json_response(conn, 200)
    assert incidente["id"] == dentro.id
    assert incidente["lat"] == -16.395
    assert incidente["lng"] == -71.535
  end

  test "200 con lista vacía si no hay incidentes", %{conn: conn} do
    conn = get(conn, ~p"/v1/map/snapshot?bbox=#{@bbox}")
    assert %{"data" => %{"incidentes" => []}} = json_response(conn, 200)
  end

  test "400 sin bbox", %{conn: conn} do
    conn = get(conn, ~p"/v1/map/snapshot")
    assert %{"error" => %{"code" => "invalid_bbox"}} = json_response(conn, 400)
  end

  test "400 con bbox inválido", %{conn: conn} do
    conn = get(conn, ~p"/v1/map/snapshot?bbox=hola")
    assert %{"error" => %{"code" => "invalid_bbox"}} = json_response(conn, 400)
  end

  test "400 con SQL en el bbox, sin tocar la base de datos", %{conn: conn} do
    bbox = URI.encode_www_form("-71.5,-16.4,-71.4,-16.3); DROP TABLE incidentes; --")
    conn = get(conn, "/v1/map/snapshot?bbox=#{bbox}")

    assert %{"error" => %{"code" => "invalid_bbox"}} = json_response(conn, 400)
  end

  describe "GET /v1/map/heat" do
    defp create(lat, lng, tipo) do
      attrs = %{"tipo" => tipo, "lat" => lat, "lng" => lng}
      {:ok, :created, incident} = Incidents.create_incident(attrs, Ecto.UUID.generate())
      incident
    end

    test "200 con las celdas, la cuenta por tipo y la franja horaria", %{conn: conn} do
      create(-16.3951, -71.5351, "robo")
      create(-16.3949, -71.5349, "robo")
      create(-16.3952, -71.5348, "pelea_colegio")

      conn = get(conn, ~p"/v1/map/heat?bbox=#{@bbox}")

      assert %{
               "data" => %{
                 "ventana" => "24h",
                 "cell_deg" => 0.0005,
                 "max" => 3,
                 "celdas" => [celda]
               }
             } = json_response(conn, 200)

      assert celda["count"] == 3
      assert celda["tipos"] == %{"robo" => 2, "pelea_colegio" => 1}
      assert %{"desde" => desde, "hasta" => hasta} = celda["franja"]
      assert hasta == desde + 3
      assert is_float(celda["lat"]) and is_float(celda["lng"])
    end

    test "es público: no pide sesión", %{conn: conn} do
      assert conn |> get(~p"/v1/map/heat?bbox=#{@bbox}") |> json_response(200)
    end

    test "200 con celdas vacías y max 0 si no hay incidentes", %{conn: conn} do
      conn = get(conn, ~p"/v1/map/heat?bbox=#{@bbox}")

      assert %{"data" => %{"celdas" => [], "max" => 0}} = json_response(conn, 200)
    end

    test "la ventana cambia lo que se cuenta", %{conn: conn} do
      reciente = create(-16.395, -71.535, "robo")
      viejo = create(-16.395, -71.535, "robo")

      viejo_en = DateTime.add(DateTime.utc_now(), -3 * 3600, :second)

      Civic.Repo.update_all(
        from(i in Civic.Incidents.Incident, where: i.id == ^viejo.id),
        set: [inserted_at: viejo_en]
      )

      una_hora = get(conn, ~p"/v1/map/heat?bbox=#{@bbox}&ventana=1h")
      un_dia = get(build_conn(), ~p"/v1/map/heat?bbox=#{@bbox}&ventana=24h")

      assert %{"data" => %{"ventana" => "1h", "celdas" => [%{"count" => 1}]}} =
               json_response(una_hora, 200)

      assert %{"data" => %{"ventana" => "24h", "celdas" => [%{"count" => 2}]}} =
               json_response(un_dia, 200)

      assert reciente.id != viejo.id
    end

    test "acepta 7d", %{conn: conn} do
      conn = get(conn, ~p"/v1/map/heat?bbox=#{@bbox}&ventana=7d")

      assert %{"data" => %{"ventana" => "7d"}} = json_response(conn, 200)
    end

    test "400 con una ventana inválida", %{conn: conn} do
      conn = get(conn, ~p"/v1/map/heat?bbox=#{@bbox}&ventana=1año")

      assert %{"error" => %{"code" => "invalid_window"}} = json_response(conn, 400)
    end

    test "400 sin bbox o con bbox inválido", %{conn: conn} do
      assert %{"error" => %{"code" => "invalid_bbox"}} =
               conn |> get(~p"/v1/map/heat") |> json_response(400)

      assert %{"error" => %{"code" => "invalid_bbox"}} =
               build_conn() |> get(~p"/v1/map/heat?bbox=1,2,3") |> json_response(400)
    end

    test "no expone ids, autores ni horas exactas", %{conn: conn} do
      create(-16.395, -71.535, "robo")

      conn = get(conn, ~p"/v1/map/heat?bbox=#{@bbox}")
      %{"data" => %{"celdas" => [celda]}} = json_response(conn, 200)

      assert celda |> Map.keys() |> Enum.sort() ==
               ["count", "franja", "lat", "lng", "tipos"]

      refute conn.resp_body =~ "reporter"
      refute conn.resp_body =~ "creado_en"
    end
  end
end
