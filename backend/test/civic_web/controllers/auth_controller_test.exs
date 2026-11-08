defmodule CivicWeb.AuthControllerTest do
  use CivicWeb.ConnCase, async: true

  alias Civic.Accounts
  alias Civic.Accounts.Sessions

  @password "una contraseña larga y segura"

  defp unique_alias, do: "Halcon-#{rem(System.unique_integer([:positive]), 1_000_000)}"

  defp json_post(conn, path, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> post(path, body)
  end

  defp register_params(overrides \\ %{}) do
    Map.merge(
      %{"alias" => unique_alias(), "password" => @password, "acepta_consentimiento" => true},
      overrides
    )
  end

  defp create_user!(alias_ \\ unique_alias()) do
    {:ok, user} =
      Accounts.register(%{
        "alias" => alias_,
        "password" => @password,
        "acepta_consentimiento" => true
      })

    user
  end

  describe "POST /v1/auth/register" do
    test "201: crea la cuenta y deja la sesión iniciada", %{conn: conn} do
      params = register_params()
      conn = json_post(conn, ~p"/v1/auth/register", params)

      assert %{
               "data" => %{
                 "user" => %{"id" => id, "alias" => alias_, "nivel" => "invitado"},
                 "access_token" => access,
                 "refresh_token" => refresh,
                 "expires_in" => 900
               }
             } = json_response(conn, 201)

      assert alias_ == params["alias"]
      assert {:ok, ^id} = Sessions.verify_access(access)
      assert {:ok, _} = Sessions.refresh(refresh)
    end

    test "la respuesta solo expone id, alias y nivel (nada de hashes ni contraseñas)",
         %{conn: conn} do
      conn = json_post(conn, ~p"/v1/auth/register", register_params())
      body = json_response(conn, 201)["data"]

      assert body["user"] |> Map.keys() |> Enum.sort() == ["alias", "id", "nivel"]
      refute conn.resp_body =~ "argon2"
      refute conn.resp_body =~ "password"
    end

    test "la respuesta no se guarda en cachés", %{conn: conn} do
      conn = json_post(conn, ~p"/v1/auth/register", register_params())
      assert get_resp_header(conn, "cache-control") == ["no-store"]
    end

    test "el cliente no puede elegir su nivel ni su id (asignación masiva)", %{conn: conn} do
      params =
        register_params(%{
          "nivel" => "verificado",
          "id" => Ecto.UUID.generate(),
          "intentos_fallidos" => -50
        })

      conn = json_post(conn, ~p"/v1/auth/register", params)

      assert %{"user" => %{"nivel" => "invitado", "id" => id}} = json_response(conn, 201)["data"]
      refute id == params["id"]
    end

    test "422: datos inválidos, con el detalle por campo y sin repetir la contraseña",
         %{conn: conn} do
      conn =
        json_post(conn, ~p"/v1/auth/register", %{
          "alias" => "x",
          "password" => "corta",
          "acepta_consentimiento" => false
        })

      assert %{"error" => %{"code" => "validation_failed", "fields" => fields}} =
               json_response(conn, 422)

      assert Map.has_key?(fields, "alias")
      assert Map.has_key?(fields, "password")
      assert Map.has_key?(fields, "acepta_consentimiento")
      refute conn.resp_body =~ "corta"
    end

    test "422 (no 500) si un campo llega con un tipo raro", %{conn: conn} do
      conn =
        json_post(conn, ~p"/v1/auth/register", %{
          "alias" => ["una", "lista"],
          "password" => %{"a" => 1},
          "acepta_consentimiento" => "quizás"
        })

      assert %{"error" => %{"code" => "validation_failed"}} = json_response(conn, 422)
    end

    test "422 si el alias ya existe, sin importar mayúsculas", %{conn: conn} do
      user = create_user!()

      conn =
        json_post(
          conn,
          ~p"/v1/auth/register",
          register_params(%{"alias" => String.upcase(user.alias)})
        )

      assert %{"error" => %{"fields" => %{"alias" => _}}} = json_response(conn, 422)
    end
  end

  describe "POST /v1/auth/login" do
    test "200: devuelve la misma forma que el registro", %{conn: conn} do
      user = create_user!()

      conn =
        json_post(conn, ~p"/v1/auth/login", %{"alias" => user.alias, "password" => @password})

      assert %{
               "data" => %{
                 "user" => %{"id" => id, "alias" => _, "nivel" => "invitado"},
                 "access_token" => access,
                 "refresh_token" => _,
                 "expires_in" => 900
               }
             } = json_response(conn, 200)

      assert id == user.id
      assert {:ok, ^id} = Sessions.verify_access(access)
    end

    test "el alias no distingue mayúsculas", %{conn: conn} do
      user = create_user!()

      conn =
        json_post(conn, ~p"/v1/auth/login", %{
          "alias" => String.downcase(user.alias),
          "password" => @password
        })

      assert json_response(conn, 200)
    end

    test "401: contraseña equivocada y alias inexistente dan EXACTAMENTE la misma respuesta",
         %{conn: conn} do
      user = create_user!()

      mala =
        conn
        |> json_post(~p"/v1/auth/login", %{"alias" => user.alias, "password" => "equivocada!!!!"})
        |> json_response(401)

      inexistente =
        build_conn()
        |> json_post(~p"/v1/auth/login", %{"alias" => "No-Existe-99", "password" => @password})
        |> json_response(401)

      assert mala == inexistente
      assert %{"error" => %{"code" => "invalid_credentials"}} = mala
    end

    test "401 (no 500) si faltan campos o llegan con tipo raro", %{conn: conn} do
      assert conn |> json_post(~p"/v1/auth/login", %{}) |> json_response(401)

      assert build_conn()
             |> json_post(~p"/v1/auth/login", %{"alias" => ["x"], "password" => 123})
             |> json_response(401)
    end

    test "tras 5 fallos la cuenta se bloquea: 429 con retry-after, ni con la clave buena entra",
         %{conn: conn} do
      user = create_user!()

      for _ <- 1..5 do
        build_conn()
        |> json_post(~p"/v1/auth/login", %{"alias" => user.alias, "password" => "equivocada!!!!"})
        |> json_response(401)
      end

      conn =
        json_post(conn, ~p"/v1/auth/login", %{"alias" => user.alias, "password" => @password})

      assert %{"error" => %{"code" => "account_locked"}} = json_response(conn, 429)
      assert [retry] = get_resp_header(conn, "retry-after")
      assert String.to_integer(retry) in 1..60
    end
  end

  describe "POST /v1/auth/refresh" do
    test "200: cambia el refresh por un par nuevo", %{conn: conn} do
      {:ok, tokens} = Sessions.issue(create_user!())

      conn = json_post(conn, ~p"/v1/auth/refresh", %{"refresh_token" => tokens.refresh_token})

      assert %{"data" => %{"access_token" => _, "refresh_token" => nuevo, "expires_in" => 900}} =
               json_response(conn, 200)

      refute nuevo == tokens.refresh_token
    end

    test "401 al reusar un refresh viejo, y el nuevo también deja de servir", %{conn: conn} do
      {:ok, tokens} = Sessions.issue(create_user!())
      {:ok, nuevo} = Sessions.refresh(tokens.refresh_token)

      conn = json_post(conn, ~p"/v1/auth/refresh", %{"refresh_token" => tokens.refresh_token})
      assert %{"error" => %{"code" => "invalid_token"}} = json_response(conn, 401)

      conn =
        json_post(build_conn(), ~p"/v1/auth/refresh", %{"refresh_token" => nuevo.refresh_token})

      assert json_response(conn, 401)
    end

    test "401 con basura, sin campo o con tipo raro", %{conn: conn} do
      for body <- [%{"refresh_token" => "basura"}, %{}, %{"refresh_token" => 123}] do
        assert build_conn()
               |> json_post(~p"/v1/auth/refresh", body)
               |> json_response(401)
      end

      _ = conn
    end
  end

  describe "POST /v1/auth/logout" do
    test "204: cierra la sesión y el refresh deja de servir", %{conn: conn} do
      {:ok, tokens} = Sessions.issue(create_user!())

      conn = json_post(conn, ~p"/v1/auth/logout", %{"refresh_token" => tokens.refresh_token})
      assert response(conn, 204) == ""

      conn =
        json_post(build_conn(), ~p"/v1/auth/refresh", %{"refresh_token" => tokens.refresh_token})

      assert json_response(conn, 401)
    end

    test "204 también con un token desconocido o sin token (no revela nada)", %{conn: conn} do
      conn = json_post(conn, ~p"/v1/auth/logout", %{"refresh_token" => "no-existe"})
      assert response(conn, 204) == ""

      conn = json_post(build_conn(), ~p"/v1/auth/logout", %{})
      assert response(conn, 204) == ""
    end
  end
end
