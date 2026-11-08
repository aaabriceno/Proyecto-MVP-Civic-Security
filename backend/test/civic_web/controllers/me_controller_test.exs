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
    assert data == %{"id" => user.id, "alias" => user.alias, "nivel" => "invitado"}
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
end
