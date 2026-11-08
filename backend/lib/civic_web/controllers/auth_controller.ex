defmodule CivicWeb.AuthController do
  @moduledoc """
  Registro, inicio de sesión, renovación y cierre de sesión.

  El controlador solo traduce HTTP a las funciones de `Civic.Accounts` y
  `Civic.Accounts.Sessions`; las reglas viven allí. Los errores los convierte
  `CivicWeb.FallbackController` al formato uniforme de la API.
  """

  use CivicWeb, :controller

  alias Civic.Accounts
  alias Civic.Accounts.Sessions

  action_fallback CivicWeb.FallbackController

  def register(conn, params) do
    with {:ok, user} <- Accounts.register(params),
         {:ok, tokens} <- Sessions.issue(user) do
      conn
      |> put_status(:created)
      |> put_view(json: CivicWeb.AuthJSON)
      |> render(:session, user: user, tokens: tokens)
    end
  end

  def login(conn, params) do
    with {:ok, user} <- Accounts.authenticate(params["alias"], params["password"]),
         {:ok, tokens} <- Sessions.issue(user) do
      conn
      |> put_view(json: CivicWeb.AuthJSON)
      |> render(:session, user: user, tokens: tokens)
    end
  end

  def refresh(conn, params) do
    with {:ok, tokens} <- Sessions.refresh(params["refresh_token"]) do
      conn
      |> put_view(json: CivicWeb.AuthJSON)
      |> render(:tokens, tokens: tokens)
    end
  end

  # Siempre 204, exista o no el token: no se revela nada
  def logout(conn, params) do
    :ok = Sessions.revoke(params["refresh_token"])
    send_resp(conn, :no_content, "")
  end
end
