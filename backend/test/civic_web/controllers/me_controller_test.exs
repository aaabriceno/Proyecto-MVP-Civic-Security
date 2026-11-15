defmodule CivicWeb.MeControllerTest do
  use CivicWeb.ConnCase, async: true

  alias Civic.Accounts
  alias Civic.Accounts.Sessions
  alias Civic.Repo

  defp create_user! do
    {:ok, user} =
      Accounts.register(%{
        "alias" => "Yo-#{rem(System.unique_integer([:positive]), 1_000_000)}",
        "password" => "una contraseña larga y segura",
        "acepta_consentimiento" => true
      })

    user
  end

  defp with_auth(conn, header_value), do: put_req_header(conn, "authorization", header_value)

  test "200: devuelve la cuenta del access token, solo con id, alias y nivel", %{conn: conn} do
    user = create_user!()
    {:ok, %{access_token: access}} = Sessions.issue(user)

    conn = conn |> with_auth("Bearer " <> access) |> get(~p"/v1/me")

    assert %{"data" => data} = json_response(conn, 200)
    assert %{"id" => id, "alias" => alias_, "nivel" => "invitado"} = data
    assert {id, alias_} == {user.id, user.alias}
  end

  test "el esquema Bearer no distingue mayúsculas", %{conn: conn} do
    {:ok, %{access_token: access}} = Sessions.issue(create_user!())

    conn = conn |> with_auth("bearer " <> access) |> get(~p"/v1/me")

    assert json_response(conn, 200)
  end

  test "401 sin cabecera Authorization, con www-authenticate y el formato de error", %{conn: conn} do
    conn = get(conn, ~p"/v1/me")

    assert %{"error" => %{"code" => "unauthorized"}} = json_response(conn, 401)
    assert get_resp_header(conn, "www-authenticate") == ["Bearer"]
  end

  test "401 (no 500) con otro esquema, token vacío, partido o basura", %{conn: conn} do
    for value <- ["Basic abc123", "Bearer", "Bearer ", "Bearer basura", "token abc", "Bearer a b"] do
      conn = conn |> recycle() |> with_auth(value) |> get(~p"/v1/me")
      assert json_response(conn, 401), "debió dar 401 con: #{inspect(value)}"
    end
  end

  test "401 con un access token de más de 15 minutos", %{conn: conn} do
    hace_16_min = DateTime.add(DateTime.utc_now(), -16 * 60, :second)
    {:ok, %{access_token: access}} = Sessions.issue(create_user!(), now: hace_16_min)

    conn = conn |> with_auth("Bearer " <> access) |> get(~p"/v1/me")

    assert json_response(conn, 401)
  end

  test "401 si se manda un refresh token en lugar del access token", %{conn: conn} do
    {:ok, %{refresh_token: refresh}} = Sessions.issue(create_user!())

    conn = conn |> with_auth("Bearer " <> refresh) |> get(~p"/v1/me")

    assert json_response(conn, 401)
  end

  test "401 si la cuenta ya no existe aunque el token siga vigente", %{conn: conn} do
    user = create_user!()
    {:ok, %{access_token: access}} = Sessions.issue(user)
    Repo.delete!(user)

    conn = conn |> with_auth("Bearer " <> access) |> get(~p"/v1/me")

    assert %{"error" => %{"code" => "unauthorized"}} = json_response(conn, 401)
  end

  describe "GET /v1/me - datos del perfil" do
    test "trae desde cuándo existe la cuenta (solo año y mes) y el cupo del día", %{conn: conn} do
      user = create_user!()
      {:ok, %{access_token: access}} = Sessions.issue(user)

      data = conn |> with_auth("Bearer " <> access) |> get(~p"/v1/me") |> json_response(200)

      assert %{"data" => %{"desde" => desde, "cupo" => %{"usados" => 0, "maximo" => 3}}} = data
      assert desde == Calendar.strftime(user.inserted_at, "%Y-%m")
    end

    test "el cupo refleja los reportes hechos", %{conn: conn} do
      user = create_user!()
      {:ok, %{access_token: access}} = Sessions.issue(user)

      for _ <- 1..2 do
        {:ok, :created, _} =
          Civic.Incidents.report_incident(
            user,
            %{"tipo" => "robo", "lat" => -16.4, "lng" => -71.53},
            Ecto.UUID.generate()
          )
      end

      data = conn |> with_auth("Bearer " <> access) |> get(~p"/v1/me") |> json_response(200)

      assert get_in(data, ["data", "cupo"]) == %{"usados" => 2, "maximo" => 3}
    end

    test "no expone el hash, los contadores ni la fecha exacta", %{conn: conn} do
      {:ok, %{access_token: access}} = Sessions.issue(create_user!())

      conn = conn |> with_auth("Bearer " <> access) |> get(~p"/v1/me")
      data = json_response(conn, 200)["data"]

      assert data |> Map.keys() |> Enum.sort() == ["alias", "cupo", "desde", "id", "nivel"]
      refute conn.resp_body =~ "argon2"
    end
  end

  describe "PUT /v1/me/password" do
    @actual "una contraseña larga y segura"
    @nueva "otra contraseña larga y distinta"

    defp put_password(conn, access, body) do
      conn
      |> with_auth("Bearer " <> access)
      |> put_req_header("content-type", "application/json")
      |> put(~p"/v1/me/password", body)
    end

    test "200: cambia la contraseña y devuelve una sesión nueva", %{conn: conn} do
      user = create_user!()
      {:ok, %{access_token: access}} = Sessions.issue(user)

      conn =
        put_password(conn, access, %{"current_password" => @actual, "new_password" => @nueva})

      assert %{
               "data" => %{"access_token" => nuevo, "refresh_token" => _, "user" => %{"id" => id}}
             } =
               json_response(conn, 200)

      assert id == user.id
      assert {:ok, ^id} = Sessions.verify_access(nuevo)
      assert {:ok, _} = Accounts.authenticate(user.alias, @nueva)
      assert {:error, :invalid_credentials} = Accounts.authenticate(user.alias, @actual)
    end

    test "cierra las demás sesiones: el refresh token anterior ya no sirve", %{conn: conn} do
      user = create_user!()
      {:ok, %{access_token: access, refresh_token: viejo}} = Sessions.issue(user)

      conn =
        put_password(conn, access, %{"current_password" => @actual, "new_password" => @nueva})

      assert json_response(conn, 200)
      assert {:error, :invalid_token} = Sessions.refresh(viejo)
    end

    test "la sesión nueva que devuelve sí se puede renovar", %{conn: conn} do
      {:ok, %{access_token: access}} = Sessions.issue(create_user!())

      conn =
        put_password(conn, access, %{"current_password" => @actual, "new_password" => @nueva})

      %{"data" => %{"refresh_token" => nuevo}} = json_response(conn, 200)
      assert {:ok, _} = Sessions.refresh(nuevo)
    end

    test "422 con la contraseña actual incorrecta, como error del campo (no 401)", %{conn: conn} do
      user = create_user!()
      {:ok, %{access_token: access}} = Sessions.issue(user)

      conn =
        put_password(conn, access, %{
          "current_password" => "no es esta!!!",
          "new_password" => @nueva
        })

      assert %{"error" => %{"code" => "validation_failed", "fields" => fields}} =
               json_response(conn, 422)

      assert %{"current_password" => [_]} = fields
      assert {:ok, _} = Accounts.authenticate(user.alias, @actual)
    end

    test "422 con una contraseña nueva que no cumple las reglas", %{conn: conn} do
      {:ok, %{access_token: access}} = Sessions.issue(create_user!())

      conn =
        put_password(conn, access, %{"current_password" => @actual, "new_password" => "corta"})

      assert %{"error" => %{"fields" => %{"new_password" => [_ | _]}}} = json_response(conn, 422)
    end

    test "422 si la nueva es igual a la actual", %{conn: conn} do
      {:ok, %{access_token: access}} = Sessions.issue(create_user!())

      conn =
        put_password(conn, access, %{"current_password" => @actual, "new_password" => @actual})

      assert %{"error" => %{"fields" => %{"new_password" => ["debe ser distinta de la actual"]}}} =
               json_response(conn, 422)
    end

    test "422 sin los campos", %{conn: conn} do
      {:ok, %{access_token: access}} = Sessions.issue(create_user!())

      conn = put_password(conn, access, %{})

      assert %{"error" => %{"code" => "validation_failed"}} = json_response(conn, 422)
    end

    test "429 tras 5 contraseñas actuales incorrectas: la cuenta se bloquea", %{conn: conn} do
      user = create_user!()
      {:ok, %{access_token: access}} = Sessions.issue(user)

      for _ <- 1..5 do
        assert put_password(build_conn(), access, %{
                 "current_password" => "no es esta!!!",
                 "new_password" => @nueva
               }).status == 422
      end

      conn =
        put_password(conn, access, %{"current_password" => @actual, "new_password" => @nueva})

      assert %{"error" => %{"code" => "account_locked"}} = json_response(conn, 429)
      assert [_] = get_resp_header(conn, "retry-after")
    end

    test "401 sin sesión", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put(~p"/v1/me/password", %{"current_password" => @actual, "new_password" => @nueva})

      assert json_response(conn, 401)
    end

    test "401 si la cuenta ya no existe", %{conn: conn} do
      user = create_user!()
      {:ok, %{access_token: access}} = Sessions.issue(user)
      Repo.delete!(user)

      conn =
        put_password(conn, access, %{"current_password" => @actual, "new_password" => @nueva})

      assert json_response(conn, 401)
    end

    test "no deja la contraseña en el log", %{conn: conn} do
      {:ok, %{access_token: access}} = Sessions.issue(create_user!())

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          put_password(conn, access, %{"current_password" => @actual, "new_password" => @nueva})
        end)

      refute log =~ @actual
      refute log =~ @nueva
    end
  end

  describe "DELETE /v1/me" do
    defp delete_me(conn, access, body) do
      conn
      |> with_auth("Bearer " <> access)
      |> put_req_header("content-type", "application/json")
      |> delete(~p"/v1/me", body)
    end

    test "204: borra la cuenta y deja de funcionar su sesión", %{conn: conn} do
      user = create_user!()
      {:ok, %{access_token: access, refresh_token: refresh}} = Sessions.issue(user)

      assert delete_me(conn, access, %{"password" => @actual}).status == 204

      assert Accounts.get_user(user.id) == nil
      assert {:error, :invalid_token} = Sessions.refresh(refresh)
      assert get(build_conn() |> with_auth("Bearer " <> access), ~p"/v1/me").status == 401
    end

    test "422 con la contraseña incorrecta y la cuenta sigue", %{conn: conn} do
      user = create_user!()
      {:ok, %{access_token: access}} = Sessions.issue(user)

      conn = delete_me(conn, access, %{"password" => "no es esta!!!"})

      assert %{"error" => %{"fields" => %{"password" => [_]}}} = json_response(conn, 422)
      assert Accounts.get_user(user.id)
    end

    test "422 sin contraseña", %{conn: conn} do
      user = create_user!()
      {:ok, %{access_token: access}} = Sessions.issue(user)

      assert delete_me(conn, access, %{}).status == 422
      assert Accounts.get_user(user.id)
    end

    test "429 cuando la cuenta está bloqueada", %{conn: conn} do
      user = create_user!()
      {:ok, %{access_token: access}} = Sessions.issue(user)
      for _ <- 1..5, do: delete_me(build_conn(), access, %{"password" => "no es esta!!!"})

      conn = delete_me(conn, access, %{"password" => @actual})

      assert %{"error" => %{"code" => "account_locked"}} = json_response(conn, 429)
      assert Accounts.get_user(user.id)
    end

    test "401 sin sesión", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> delete(~p"/v1/me", %{"password" => @actual})

      assert json_response(conn, 401)
    end

    test "los reportes de la cuenta siguen en el mapa", %{conn: conn} do
      user = create_user!()
      {:ok, %{access_token: access}} = Sessions.issue(user)

      {:ok, :created, incidente} =
        Civic.Incidents.report_incident(
          user,
          %{"tipo" => "robo", "lat" => -16.4, "lng" => -71.53},
          Ecto.UUID.generate()
        )

      assert delete_me(conn, access, %{"password" => @actual}).status == 204

      assert Repo.get(Civic.Incidents.Incident, incidente.id)
    end
  end
end
