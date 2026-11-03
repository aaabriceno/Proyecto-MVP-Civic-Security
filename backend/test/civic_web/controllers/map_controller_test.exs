defmodule CivicWeb.MapControllerTest do
  use CivicWeb.ConnCase, async: true

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
end
