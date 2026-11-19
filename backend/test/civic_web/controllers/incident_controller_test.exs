defmodule CivicWeb.IncidentControllerTest do
  use CivicWeb.ConnCase, async: true

  alias Civic.Accounts
  alias Civic.Accounts.Sessions
  alias Civic.Incidents.Incident
  alias Civic.Repo

  @valid %{
    "tipo" => "robo",
    "lat" => -16.3963,
    "lng" => -71.5340,
    "descripcion" => "Me robaron el celular"
  }

  defp create_user! do
    {:ok, user} =
      Accounts.register(%{
        "alias" => "Yo-#{rem(System.unique_integer([:positive]), 1_000_000)}",
        "password" => "una contraseña larga y segura",
        "acepta_consentimiento" => true
      })

    user
  end

  # Una conexión nueva con la sesión de `user`
  defp auth_conn(user) do
    {:ok, %{access_token: access}} = Sessions.issue(user)
    put_req_header(build_conn(), "authorization", "Bearer " <> access)
  end

  setup do
    user = create_user!()
    {:ok, user: user, conn: auth_conn(user)}
  end

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

    # Un reporte nuevo empieza sin votos
    assert %{"confirmaciones" => 0, "falsos" => 0} = data

    assert Map.keys(data) |> Enum.sort() ==
             ~w(confirmaciones creado_en descripcion estado falsos id lat lng tiene_foto tipo)
  end

  test "200 al repetir la misma idempotency-key devuelve el mismo id", %{conn: conn, user: user} do
    key = Ecto.UUID.generate()
    id = conn |> post_incident(@valid, key) |> json_response(201) |> get_in(["data", "id"])

    conn = post_incident(auth_conn(user), @valid, key)
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

  test "409 si la misma idempotency-key llega con otro contenido", %{conn: conn, user: user} do
    key = Ecto.UUID.generate()
    assert conn |> post_incident(@valid, key) |> json_response(201)

    conn = post_incident(auth_conn(user), %{@valid | "tipo" => "pelea_colegio"}, key)
    assert %{"error" => %{"code" => "idempotency_key_conflict"}} = json_response(conn, 409)
  end

  describe "sesión obligatoria" do
    test "401 sin sesión, con el formato de error, y no se crea nada" do
      conn = post_incident(build_conn(), @valid, Ecto.UUID.generate())

      assert %{"error" => %{"code" => "unauthorized"}} = json_response(conn, 401)
      assert get_resp_header(conn, "www-authenticate") == ["Bearer"]
      assert Repo.aggregate(Incident, :count) == 0
    end

    test "401 con un token manipulado" do
      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer esto.no.es.un.token")
        |> post_incident(@valid, Ecto.UUID.generate())

      assert json_response(conn, 401)
      assert Repo.aggregate(Incident, :count) == 0
    end

    test "401 si el token sigue vigente pero la cuenta ya no existe" do
      user = create_user!()
      conn = auth_conn(user)
      Repo.delete!(user)

      conn = post_incident(conn, @valid, Ecto.UUID.generate())

      assert json_response(conn, 401)
      assert Repo.aggregate(Incident, :count) == 0
    end

    test "sin sesión no se emite nada por el canal en vivo" do
      CivicWeb.Endpoint.subscribe("mapa:arequipa")

      conn = post_incident(build_conn(), @valid, Ecto.UUID.generate())

      assert json_response(conn, 401)
      refute_receive %Phoenix.Socket.Broadcast{}
    end

    test "el incidente guarda el token del autor, nunca el id de la cuenta", %{
      conn: conn,
      user: user
    } do
      conn = post_incident(conn, @valid, Ecto.UUID.generate())
      id = json_response(conn, 201)["data"]["id"]

      incident = Repo.get!(Incident, id)
      assert incident.reporter_token == Civic.Privacy.reporter_token(user.id, id)
    end

    test "409 si otra cuenta usa la idempotency-key de un reporte ajeno", %{conn: conn} do
      key = Ecto.UUID.generate()
      assert conn |> post_incident(@valid, key) |> json_response(201)

      conn = post_incident(auth_conn(create_user!()), @valid, key)

      assert %{"error" => %{"code" => "idempotency_key_conflict"}} = json_response(conn, 409)
    end
  end

  describe "cupo diario por cuenta" do
    test "429 al pasar el cupo, con retry-after y sin crear el incidente", %{
      conn: conn,
      user: user
    } do
      for _ <- 1..3,
          do: assert(conn |> post_incident(@valid, Ecto.UUID.generate()) |> json_response(201))

      conn = post_incident(auth_conn(user), @valid, Ecto.UUID.generate())

      assert %{"error" => %{"code" => "report_quota_exceeded"}} = json_response(conn, 429)
      assert [segundos] = get_resp_header(conn, "retry-after")
      assert String.to_integer(segundos) > 0
      assert Repo.aggregate(Incident, :count) == 3
    end

    test "el cupo agotado no se emite por el canal en vivo", %{user: user} do
      for _ <- 1..3, do: post_incident(auth_conn(user), @valid, Ecto.UUID.generate())

      CivicWeb.Endpoint.subscribe("mapa:arequipa")
      conn = post_incident(auth_conn(user), @valid, Ecto.UUID.generate())

      assert json_response(conn, 429)
      refute_receive %Phoenix.Socket.Broadcast{}
    end

    test "agotar el cupo de una cuenta no afecta a otra", %{user: user} do
      for _ <- 1..3, do: post_incident(auth_conn(user), @valid, Ecto.UUID.generate())

      conn = post_incident(auth_conn(create_user!()), @valid, Ecto.UUID.generate())

      assert json_response(conn, 201)
    end
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

    test "repetir la misma idempotency-key no vuelve a emitir", %{conn: conn, user: user} do
      key = Ecto.UUID.generate()
      post_incident(conn, @valid, key)

      CivicWeb.Endpoint.subscribe("mapa:arequipa")
      conn = post_incident(auth_conn(user), @valid, key)

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
