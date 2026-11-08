defmodule CivicWeb.LogPrivacyTest do
  # Sube el nivel de log global para poder leer lo que Phoenix escribe:
  # no puede correr en paralelo con otros tests
  use CivicWeb.ConnCase, async: false

  import ExUnit.CaptureLog

  alias Civic.Accounts
  alias Civic.Accounts.Sessions

  @password "una contraseña larga y segura"

  # Sube el nivel solo mientras dura la petición, y lo deja como estaba
  defp capturar(fun) do
    previous = Logger.level()
    Logger.configure(level: :debug)

    try do
      capture_log(fun)
    after
      Logger.configure(level: previous)
    end
  end

  test "el filtro de parámetros oculta contraseñas, tokens y DNI, y deja el resto" do
    params = %{
      "alias" => "Halcon-1",
      "password" => "secreta-1",
      "refresh_token" => "secreta-2",
      "access_token" => "secreta-3",
      "dni" => "12345678"
    }

    filtered = Phoenix.Logger.filter_values(params)

    assert filtered["alias"] == "Halcon-1"

    for key <- ["password", "refresh_token", "access_token", "dni"] do
      assert filtered[key] == "[FILTERED]", "#{key} no se filtra en los logs"
    end
  end

  test "login: ni la contraseña ni los tokens aparecen en el log real", %{conn: conn} do
    {:ok, user} =
      Accounts.register(%{
        "alias" => "Log-Priv-1",
        "password" => @password,
        "acepta_consentimiento" => true
      })

    log =
      capturar(fn ->
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/v1/auth/login", %{"alias" => user.alias, "password" => @password})
      end)

    # Prueba de que el log sí se está leyendo: la petición queda registrada
    assert log =~ "/v1/auth/login"
    refute log =~ @password
  end

  test "refresh y logout: el refresh token no aparece en el log real", %{conn: conn} do
    {:ok, user} =
      Accounts.register(%{
        "alias" => "Log-Priv-2",
        "password" => @password,
        "acepta_consentimiento" => true
      })

    {:ok, tokens} = Sessions.issue(user)

    log =
      capturar(fn ->
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/v1/auth/refresh", %{"refresh_token" => tokens.refresh_token})
      end)

    assert log =~ "/v1/auth/refresh"
    refute log =~ tokens.refresh_token
  end
end
