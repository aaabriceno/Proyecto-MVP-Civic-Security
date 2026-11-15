defmodule CivicWeb.PhotoControllerTest do
  # Sube fotos, y eso emite por el canal en vivo "mapa:arequipa", que es global:
  # en paralelo se colaría en las pruebas que vigilan que NO se emita nada
  use CivicWeb.ConnCase, async: false

  import Civic.JpegFixtures

  alias Civic.Accounts
  alias Civic.Accounts.Sessions
  alias Civic.Evidence
  alias Civic.Incidents
  alias Civic.Incidents.Incident
  alias Civic.Repo

  defp create_user! do
    {:ok, user} =
      Accounts.register(%{
        "alias" => "Foto-#{System.unique_integer([:positive])}",
        "password" => "una contraseña larga y segura",
        "acepta_consentimiento" => true
      })

    user
  end

  defp report!(user) do
    {:ok, :created, incident} =
      Incidents.report_incident(
        user,
        %{"tipo" => "robo", "lat" => -16.4, "lng" => -71.53},
        Ecto.UUID.generate()
      )

    incident
  end

  defp auth(conn, user) do
    {:ok, %{access_token: access}} = Sessions.issue(user)
    put_req_header(conn, "authorization", "Bearer " <> access)
  end

  defp put_photo(conn, id, body, content_type \\ "image/jpeg") do
    conn
    |> put_req_header("content-type", content_type)
    |> put(~p"/v1/incidents/#{id}/photo", body)
  end

  setup %{conn: conn} do
    author = create_user!()
    {:ok, author: author, incident: report!(author), conn: auth(conn, author)}
  end

  describe "PUT /v1/incidents/:id/photo" do
    test "201: el autor sube su foto y el incidente dice que la tiene", %{conn: conn, incident: i} do
      conn = put_photo(conn, i.id, clean())

      assert %{"data" => %{"id" => id, "tiene_foto" => true}} = json_response(conn, 201)
      assert id == i.id
      assert Repo.get!(Incident, i.id).tiene_foto
    end

    test "acepta el tipo con parámetros y en mayúsculas", %{conn: conn, incident: i} do
      conn = put_photo(conn, i.id, clean(), "Image/JPEG; charset=binary")

      assert json_response(conn, 201)
    end

    test "avisa por el canal en vivo que el reporte ahora tiene foto", %{conn: conn, incident: i} do
      CivicWeb.Endpoint.subscribe("mapa:arequipa")

      conn = put_photo(conn, i.id, clean())
      assert json_response(conn, 201)

      id = i.id

      assert_receive %Phoenix.Socket.Broadcast{
        event: "incidente_actualizado",
        payload: %{id: ^id, tiene_foto: true}
      }
    end

    test "401 sin sesión", %{incident: i} do
      conn = put_photo(build_conn(), i.id, clean())

      assert %{"error" => %{"code" => "unauthorized"}} = json_response(conn, 401)
    end

    test "403 not_author: otra cuenta no puede subir foto a un reporte ajeno", %{incident: i} do
      conn = put_photo(auth(build_conn(), create_user!()), i.id, clean())

      assert %{"error" => %{"code" => "not_author"}} = json_response(conn, 403)
      refute Repo.get!(Incident, i.id).tiene_foto
    end

    test "404 not_found: el reporte no existe o el id no es un UUID", %{author: author} do
      for id <- [Ecto.UUID.generate(), "abc", "no-es-un-uuid"] do
        conn = auth(build_conn(), author)
        conn = put_photo(conn, id, clean())

        assert %{"error" => %{"code" => "not_found"}} = json_response(conn, 404), id
      end
    end

    test "409 photo_exists: ya tiene foto, y se conserva la primera", %{conn: conn, incident: i} do
      assert conn |> put_photo(i.id, clean()) |> json_response(201)

      conn = conn |> recycle() |> put_photo(i.id, fixture("progresiva"))

      assert %{"error" => %{"code" => "photo_exists"}} = json_response(conn, 409)
      assert Evidence.fetch_photo(i.id) == {:ok, clean()}
    end

    test "422 photo_has_metadata: trae GPS, modelo del teléfono o fecha", %{
      conn: conn,
      incident: i
    } do
      conn = put_photo(conn, i.id, fixture("con_exif_gps"))

      assert %{"error" => %{"code" => "photo_has_metadata", "message" => mensaje}} =
               json_response(conn, 422)

      assert mensaje =~ "ubicación"
      refute Repo.get!(Incident, i.id).tiene_foto
    end

    test "422 invalid_photo: no es un JPEG válido", %{incident: i, author: author} do
      for malo <- ["no soy una foto", <<0x89, "PNG", 0::64>>, binary_part(clean(), 0, 100)] do
        conn = auth(build_conn(), author)
        conn = put_photo(conn, i.id, malo)

        assert %{"error" => %{"code" => "invalid_photo"}} = json_response(conn, 422)
      end
    end

    test "413 photo_too_large: más de 2 MB", %{conn: conn, incident: i} do
      conn = put_photo(conn, i.id, clean() <> :binary.copy(<<0>>, Evidence.max_bytes()))

      assert %{"error" => %{"code" => "photo_too_large"}} = json_response(conn, 413)
      refute Repo.get!(Incident, i.id).tiene_foto
    end

    test "413 también si el encabezado ya anuncia un tamaño enorme", %{conn: conn, incident: i} do
      conn =
        conn
        |> put_req_header("content-length", Integer.to_string(Evidence.max_bytes() * 10))
        |> put_photo(i.id, clean())

      assert %{"error" => %{"code" => "photo_too_large"}} = json_response(conn, 413)
    end

    test "una foto enviada como JSON se rechaza como petición mal formada (400)", %{
      incident: i,
      author: author
    } do
      assert_error_sent 400, fn ->
        put_photo(auth(build_conn(), author), i.id, clean(), "application/json")
      end

      refute Repo.get!(Incident, i.id).tiene_foto
    end

    test "415: solo se acepta image/jpeg", %{incident: i, author: author} do
      for tipo <- ["image/png", "application/octet-stream", "text/plain", "multipart/form-data"] do
        assert_error_sent 415, fn ->
          put_photo(auth(build_conn(), author), i.id, clean(), tipo)
        end
      end

      refute Repo.get!(Incident, i.id).tiene_foto
    end

    test "415 sin encabezado content-type (el parser de Plug lo deja pasar en silencio)", %{
      conn: conn,
      incident: i
    } do
      # Con parámetros en vez de cuerpo el cliente de pruebas no agrega content-type
      conn = put(conn, ~p"/v1/incidents/#{i.id}/photo", %{})

      assert %{"error" => %{"code" => "unsupported_media_type"}} = json_response(conn, 415)
      refute Repo.get!(Incident, i.id).tiene_foto
    end

    test "una foto con metadatos no pasa aunque venga por el camino normal", %{
      incident: i,
      author: author
    } do
      for nombre <- ["con_xmp", "con_icc", "con_comentario"] do
        conn = auth(build_conn(), author)
        conn = put_photo(conn, i.id, fixture(nombre))

        assert %{"error" => %{"code" => "photo_has_metadata"}} = json_response(conn, 422), nombre
      end
    end
  end

  describe "GET /v1/incidents/:id/photo" do
    setup %{conn: conn, incident: i} do
      assert conn |> put_photo(i.id, clean()) |> json_response(201)
      :ok
    end

    test "200: cualquiera puede ver la foto, sin sesión (como el mapa)", %{incident: i} do
      conn = get(build_conn(), ~p"/v1/incidents/#{i.id}/photo")

      assert response(conn, 200) == clean()
      assert [tipo] = get_resp_header(conn, "content-type")
      assert tipo =~ "image/jpeg"
      refute tipo =~ "charset"
    end

    test "se sirve con nosniff y sin guardarse en cachés", %{incident: i} do
      conn = get(build_conn(), ~p"/v1/incidents/#{i.id}/photo")

      assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
      assert get_resp_header(conn, "cache-control") == ["no-store"]
    end

    test "acepta una petición con Accept: image/jpeg", %{incident: i} do
      conn =
        build_conn()
        |> put_req_header("accept", "image/jpeg")
        |> get(~p"/v1/incidents/#{i.id}/photo")

      assert response(conn, 200) == clean()
    end

    test "404 not_found: un reporte sin foto, que no existe o con id inválido", %{conn: conn} do
      otro = report!(create_user!())

      for id <- [otro.id, Ecto.UUID.generate(), "abc", "../../etc/passwd"] do
        conn = get(build_conn(), "/v1/incidents/#{URI.encode_www_form(id)}/photo")

        assert %{"error" => %{"code" => "not_found"}} = json_response(conn, 404), id
      end

      _ = conn
    end

    test "404 si el reporte fue descartado", %{incident: i} do
      i |> Ecto.Changeset.change(estado: :descartado) |> Repo.update!()

      conn = get(build_conn(), ~p"/v1/incidents/#{i.id}/photo")

      assert json_response(conn, 404)
    end
  end

  describe "tiene_foto en el resto de la API" do
    test "el snapshot del mapa dice cuáles reportes tienen foto", %{conn: conn, incident: i} do
      otro = report!(create_user!())
      assert conn |> put_photo(i.id, clean()) |> json_response(201)

      conn =
        get(build_conn(), ~p"/v1/map/snapshot", %{"bbox" => "-71.75,-16.60,-71.40,-16.25"})

      por_id =
        for inc <- json_response(conn, 200)["data"]["incidentes"], into: %{}, do: {inc["id"], inc}

      assert por_id[i.id]["tiene_foto"] == true
      assert por_id[otro.id]["tiene_foto"] == false
    end

    test "al crear un reporte el cliente no puede declarar que ya tiene foto", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("idempotency-key", Ecto.UUID.generate())
        |> post(~p"/v1/incidents", %{
          "tipo" => "robo",
          "lat" => -16.4,
          "lng" => -71.53,
          "tiene_foto" => true
        })

      assert %{"data" => %{"id" => id, "tiene_foto" => false}} = json_response(conn, 201)
      assert Evidence.fetch_photo(id) == {:error, :not_found}
    end
  end
end
