defmodule CivicWeb.VoteControllerTest do
  # Votar emite por el canal en vivo "mapa:arequipa", que es global: en paralelo se
  # colaría en las pruebas que vigilan que NO se emita nada
  use CivicWeb.ConnCase, async: false

  alias Civic.Accounts
  alias Civic.Accounts.{Sessions, Verification}
  alias Civic.Incidents
  alias Civic.Incidents.Incident
  alias Civic.Repo

  @lat -16.4
  @lng -71.53

  defp create_user! do
    {:ok, user} =
      Accounts.register(%{
        "alias" => "Voto-#{System.unique_integer([:positive])}",
        "password" => "una contraseña larga y segura",
        "acepta_consentimiento" => true
      })

    user
  end

  defp dni do
    [:positive]
    |> System.unique_integer()
    |> rem(100_000_000)
    |> Integer.to_string()
    |> String.pad_leading(8, "0")
  end

  defp verified! do
    {:ok, user} = Verification.verify_dni(create_user!(), dni())
    user
  end

  defp report!(user) do
    {:ok, :created, incident} =
      Incidents.report_incident(
        user,
        %{"tipo" => "robo", "lat" => @lat, "lng" => @lng},
        Ecto.UUID.generate()
      )

    incident
  end

  defp auth(conn, user) do
    {:ok, %{access_token: access}} = Sessions.issue(user)
    put_req_header(conn, "authorization", "Bearer " <> access)
  end

  defp body(valor, extra \\ %{}),
    do: Map.merge(%{"valor" => valor, "lat" => @lat + 0.002, "lng" => @lng}, extra)

  defp votar(conn, id, params), do: post(conn, ~p"/v1/incidents/#{id}/votes", params)

  # Una petición nueva con la sesión de `user`
  defp como(user), do: auth(build_conn(), user)

  setup do
    author = verified!()
    {:ok, author: author, incident: report!(author)}
  end

  describe "POST /v1/incidents/:id/votes" do
    test "201: confirma y devuelve el reporte con sus contadores", %{incident: i} do
      conn = votar(como(verified!()), i.id, body("confirmo"))

      assert %{"data" => data} = json_response(conn, 201)
      assert data["id"] == i.id
      assert data["confirmaciones"] == 1
      assert data["falsos"] == 0
      assert data["estado"] == "sin_verificar"
    end

    test "con 3 confirmaciones el reporte queda Verificado", %{incident: i} do
      for _ <- 1..2,
          do: assert(json_response(votar(como(verified!()), i.id, body("confirmo")), 201))

      conn = votar(como(verified!()), i.id, body("confirmo"))

      assert %{"data" => %{"estado" => "verificado", "confirmaciones" => 3}} =
               json_response(conn, 201)

      assert Repo.get!(Incident, i.id).estado == :verificado
    end

    test "con 3 falsos el reporte queda Descartado", %{incident: i} do
      for _ <- 1..3, do: assert(json_response(votar(como(verified!()), i.id, body("falso")), 201))

      assert Repo.get!(Incident, i.id).estado == :descartado
    end

    test "la respuesta no dice quién votó", %{incident: i} do
      conn = votar(como(verified!()), i.id, body("confirmo"))

      assert %{"data" => data} = json_response(conn, 201)

      assert data |> Map.keys() |> Enum.sort() ==
               ~w(confirmaciones creado_en descripcion estado falsos id lat lng tiene_foto tipo)
    end

    test "avisa por el canal en vivo para que los otros mapas lo vean", %{incident: i} do
      CivicWeb.Endpoint.subscribe("mapa:arequipa")

      conn = votar(como(verified!()), i.id, body("confirmo"))
      assert json_response(conn, 201)

      id = i.id

      assert_receive %Phoenix.Socket.Broadcast{
        event: "incidente_actualizado",
        payload: %{id: ^id, confirmaciones: 1, estado: :sin_verificar}
      }
    end

    test "401 sin sesión", %{conn: conn, incident: i} do
      conn = votar(conn, i.id, body("confirmo"))

      assert %{"error" => %{"code" => "unauthorized"}} = json_response(conn, 401)
    end

    test "403 not_verified: una cuenta sin verificar no puede votar", %{incident: i} do
      conn = votar(como(create_user!()), i.id, body("confirmo"))

      assert %{"error" => %{"code" => "not_verified"}} = json_response(conn, 403)
      assert Repo.get!(Incident, i.id).confirmaciones == 0
    end

    test "403 own_report: el autor no puede votar su propio reporte", %{
      author: author,
      incident: i
    } do
      conn = votar(como(author), i.id, body("confirmo"))

      assert %{"error" => %{"code" => "own_report"}} = json_response(conn, 403)
    end

    test "409 already_voted: segunda vez", %{incident: i} do
      votante = verified!()
      assert json_response(votar(como(votante), i.id, body("confirmo")), 201)

      conn = votar(como(votante), i.id, body("falso"))

      assert %{"error" => %{"code" => "already_voted"}} = json_response(conn, 409)
      assert Repo.get!(Incident, i.id).falsos == 0
    end

    test "409 voting_closed: el reporte ya se resolvió", %{incident: i} do
      for _ <- 1..3,
          do: assert(json_response(votar(como(verified!()), i.id, body("confirmo")), 201))

      conn = votar(como(verified!()), i.id, body("confirmo"))

      assert %{"error" => %{"code" => "voting_closed"}} = json_response(conn, 409)
    end

    test "422 too_far: hay que estar cerca del lugar", %{incident: i} do
      conn = votar(como(verified!()), i.id, body("confirmo", %{"lat" => @lat + 0.05}))

      assert %{"error" => %{"code" => "too_far"}} = json_response(conn, 422)
      assert Repo.get!(Incident, i.id).confirmaciones == 0
    end

    test "422: el valor debe ser confirmo o falso", %{incident: i} do
      for malo <- ["si", "", nil, 1] do
        conn = votar(como(verified!()), i.id, body(malo))

        assert %{"error" => %{"code" => "validation_failed", "fields" => %{"valor" => [_]}}} =
                 json_response(conn, 422)
      end
    end

    test "422: sin ubicación válida no se puede votar", %{incident: i} do
      for params <- [
            %{"valor" => "confirmo"},
            %{"valor" => "confirmo", "lat" => "x", "lng" => "y"},
            %{"valor" => "confirmo", "lat" => 100, "lng" => 0}
          ] do
        conn = votar(como(verified!()), i.id, params)

        assert %{"error" => %{"code" => "validation_failed", "fields" => %{"ubicacion" => [_]}}} =
                 json_response(conn, 422)
      end
    end

    test "404 not_found: el reporte no existe o el id no es un UUID" do
      for id <- [Ecto.UUID.generate(), "abc", "no-es-un-uuid"] do
        conn = votar(como(verified!()), id, body("confirmo"))

        assert %{"error" => %{"code" => "not_found"}} = json_response(conn, 404), id
      end
    end

    test "un voto rechazado no emite nada por el canal en vivo", %{incident: i} do
      CivicWeb.Endpoint.subscribe("mapa:arequipa")

      conn = votar(como(create_user!()), i.id, body("confirmo"))
      assert json_response(conn, 403)

      refute_receive %Phoenix.Socket.Broadcast{event: "incidente_actualizado"}
    end
  end
end
