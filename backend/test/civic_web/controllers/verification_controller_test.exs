defmodule CivicWeb.VerificationControllerTest do
  use CivicWeb.ConnCase, async: true

  alias Civic.Accounts
  alias Civic.Accounts.{Sessions, User}
  alias Civic.Repo

  defp create_user! do
    {:ok, user} =
      Accounts.register(%{
        "alias" => "Dni-#{System.unique_integer([:positive])}",
        "password" => "una contraseña larga y segura",
        "acepta_consentimiento" => true
      })

    user
  end

  # Un DNI distinto en cada llamada (ver Civic.Accounts.VerificationTest)
  defp dni do
    [:positive]
    |> System.unique_integer()
    |> rem(100_000_000)
    |> Integer.to_string()
    |> String.pad_leading(8, "0")
  end

  defp con_sesion(conn, user) do
    {:ok, %{access_token: access}} = Sessions.issue(user)
    put_req_header(conn, "authorization", "Bearer " <> access)
  end

  defp verificar(conn, user, dni),
    do: conn |> con_sesion(user) |> post(~p"/v1/verification/dni", %{"dni" => dni})

  test "401 sin sesión", %{conn: conn} do
    conn = post(conn, ~p"/v1/verification/dni", %{"dni" => dni()})

    assert %{"error" => %{"code" => "unauthorized"}} = json_response(conn, 401)
  end

  test "200: verifica la cuenta y devuelve el perfil con el cupo mayor", %{conn: conn} do
    user = create_user!()

    conn = verificar(conn, user, dni())

    assert %{"data" => data} = json_response(conn, 200)
    assert data["id"] == user.id
    assert data["nivel"] == "verificado"
    assert data["cupo"] == %{"usados" => 0, "maximo" => 10}
    assert Repo.get!(User, user.id).nivel == :verificado
  end

  test "después de verificar, GET /me también dice verificado", %{conn: conn} do
    user = create_user!()
    conn = verificar(conn, user, dni())
    assert json_response(conn, 200)

    conn = conn |> recycle() |> con_sesion(user) |> get(~p"/v1/me")

    assert %{"data" => %{"nivel" => "verificado"}} = json_response(conn, 200)
  end

  test "la respuesta no devuelve el DNI ni su huella", %{conn: conn} do
    user = create_user!()
    dni = dni()

    conn = verificar(conn, user, dni)

    body = response(conn, 200)
    refute body =~ dni
    # Solo los campos de siempre del perfil: ni `verif_hash` ni `verif_version`
    assert %{"data" => data} = Jason.decode!(body)
    assert data |> Map.keys() |> Enum.sort() == ["alias", "cupo", "desde", "id", "nivel"]
  end

  test "409 dni_taken: el DNI ya tiene otra cuenta", %{conn: conn} do
    dni = dni()
    assert conn |> verificar(create_user!(), dni) |> json_response(200)

    otra = create_user!()
    conn = conn |> recycle() |> verificar(otra, dni)

    assert %{"error" => %{"code" => "dni_taken", "message" => mensaje}} = json_response(conn, 409)
    assert mensaje =~ "ya tiene una cuenta"
    refute mensaje =~ dni
    assert Repo.get!(User, otra.id).nivel == :invitado
  end

  test "409 already_verified: la cuenta ya está verificada", %{conn: conn} do
    user = create_user!()
    assert conn |> verificar(user, dni()) |> json_response(200)

    conn = conn |> recycle() |> verificar(user, dni())

    assert %{"error" => %{"code" => "already_verified"}} = json_response(conn, 409)
  end

  test "422 con el campo dni cuando no tiene 8 dígitos, sin repetir lo enviado", %{conn: conn} do
    user = create_user!()

    for malo <- ["1234567", "abcdefgh", "123456789", ""] do
      conn = conn |> recycle() |> verificar(user, malo)

      assert %{"error" => %{"code" => "validation_failed", "fields" => %{"dni" => [mensaje]}}} =
               json_response(conn, 422)

      assert mensaje =~ "8 dígitos"
      # "" está contenido en cualquier texto: solo tiene sentido buscar lo demás
      if malo != "", do: refute(mensaje =~ malo)
    end
  end

  test "422 si falta el campo o no es texto", %{conn: conn} do
    user = create_user!()

    for body <- [%{}, %{"dni" => 12_345_678}, %{"dni" => ["12345678"]}, %{"dni" => nil}] do
      conn = conn |> recycle() |> con_sesion(user) |> post(~p"/v1/verification/dni", body)

      assert %{"error" => %{"fields" => %{"dni" => _}}} = json_response(conn, 422)
    end
  end

  test "429 dni_attempts_exceeded con retry-after tras 5 intentos", %{conn: conn} do
    ocupado = dni()
    assert conn |> verificar(create_user!(), ocupado) |> json_response(200)

    user = create_user!()

    for _ <- 1..5 do
      conn = conn |> recycle() |> verificar(user, ocupado)
      assert json_response(conn, 409)
    end

    conn = conn |> recycle() |> verificar(user, dni())

    assert %{"error" => %{"code" => "dni_attempts_exceeded"}} = json_response(conn, 429)
    assert [retry_after] = get_resp_header(conn, "retry-after")
    assert String.to_integer(retry_after) > 0
  end
end
