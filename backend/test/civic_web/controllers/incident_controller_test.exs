defmodule CivicWeb.IncidentControllerTest do
  use CivicWeb.ConnCase, async: true

  @valid %{
    "tipo" => "robo",
    "lat" => -16.3963,
    "lng" => -71.5340,
    "descripcion" => "Me robaron el celular"
  }

  defp post_incident(conn, body, key) do
    conn
    |> put_req_header("content-type", "application/json")
    |> put_req_header("idempotency-key", key)
    |> post(~p"/v1/incidents", body)
  end

  test "201 con un incidente nuevo", %{conn: conn} do
    conn = post_incident(conn, @valid, Ecto.UUID.generate())
    data = json_response(conn, 201)["data"]

    assert %{
             "tipo" => "robo",
             "lat" => -16.3963,
             "lng" => -71.534,
             "descripcion" => "Me robaron el celular",
             "estado" => "sin_verificar"
           } = data

    assert Map.keys(data) |> Enum.sort() ==
             ["creado_en", "descripcion", "estado", "id", "lat", "lng", "tipo"]
  end

  test "200 al repetir la misma idempotency-key devuelve el mismo id", %{conn: conn} do
    key = Ecto.UUID.generate()
    id = conn |> post_incident(@valid, key) |> json_response(201) |> get_in(["data", "id"])

    conn = post_incident(build_conn(), @valid, key)
    assert json_response(conn, 200)["data"]["id"] == id
  end

  test "400 sin idempotency-key", %{conn: conn} do
    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> post(~p"/v1/incidents", @valid)

    assert %{"error" => %{"code" => "idempotency_key_required"}} = json_response(conn, 400)
  end

  test "400 si la idempotency-key no es un UUID", %{conn: conn} do
    conn = post_incident(conn, @valid, "no-soy-uuid")
    assert %{"error" => %{"code" => "idempotency_key_required"}} = json_response(conn, 400)
  end

  test "422 fuera de Arequipa, con el error en fields", %{conn: conn} do
    body = %{@valid | "lat" => -12.05, "lng" => -77.04}
    conn = post_incident(conn, body, Ecto.UUID.generate())

    assert %{
             "error" => %{
               "code" => "validation_failed",
               "fields" => %{"ubicacion" => ["La ubicación debe estar dentro de Arequipa"]}
             }
           } = json_response(conn, 422)
  end

  test "la respuesta no expone ubicacion ni idempotency_key", %{conn: conn} do
    conn = post_incident(conn, @valid, Ecto.UUID.generate())
    data = json_response(conn, 201)["data"]

    refute Map.has_key?(data, "ubicacion")
    refute Map.has_key?(data, "idempotency_key")
  end

  test "una descripción con SQL se guarda como texto inofensivo", %{conn: conn} do
    sql = "'); DROP TABLE incidentes; --"
    conn = post_incident(conn, %{@valid | "descripcion" => sql}, Ecto.UUID.generate())

    assert json_response(conn, 201)["data"]["descripcion"] == sql
    assert Civic.Repo.aggregate(Civic.Incidents.Incident, :count) == 1
  end

  test "409 si la misma idempotency-key llega con otro contenido", %{conn: conn} do
    key = Ecto.UUID.generate()
    assert conn |> post_incident(@valid, key) |> json_response(201)

    conn = post_incident(build_conn(), %{@valid | "tipo" => "pelea_colegio"}, key)
    assert %{"error" => %{"code" => "idempotency_key_conflict"}} = json_response(conn, 409)
  end

  describe "tiempo real" do
    test "un reporte nuevo se emite en mapa:arequipa", %{conn: conn} do
      CivicWeb.Endpoint.subscribe("mapa:arequipa")

      conn = post_incident(conn, @valid, Ecto.UUID.generate())
      %{"id" => id} = json_response(conn, 201)["data"]

      assert_receive %Phoenix.Socket.Broadcast{
        topic: "mapa:arequipa",
        event: "incidente_nuevo",
        payload: %{id: ^id, tipo: :robo, estado: :sin_verificar}
      }
    end

    test "repetir la misma idempotency-key no vuelve a emitir", %{conn: conn} do
      key = Ecto.UUID.generate()
      post_incident(conn, @valid, key)

      CivicWeb.Endpoint.subscribe("mapa:arequipa")
      conn = post_incident(build_conn(), @valid, key)

      assert json_response(conn, 200)
      refute_receive %Phoenix.Socket.Broadcast{}
    end

    test "un reporte rechazado no se emite", %{conn: conn} do
      CivicWeb.Endpoint.subscribe("mapa:arequipa")

      conn =
        post_incident(conn, %{@valid | "lat" => -12.05, "lng" => -77.04}, Ecto.UUID.generate())

      assert json_response(conn, 422)
      refute_receive %Phoenix.Socket.Broadcast{}
    end
  end
end
