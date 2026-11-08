defmodule CivicWeb.MeController do
  @moduledoc "La cuenta de quien hace la petición (ruta protegida por `Plugs.Authenticate`)."

  use CivicWeb, :controller

  alias Civic.Accounts
  alias Civic.Accounts.User

  action_fallback CivicWeb.FallbackController

  def show(conn, _params) do
    # El token puede seguir vigente (15 min) aunque la cuenta ya se haya borrado
    with %User{} = user <- Accounts.get_user(conn.assigns.current_user_id) do
      conn
      |> put_view(json: CivicWeb.AuthJSON)
      |> render(:me, user: user)
    else
      nil -> {:error, :unauthorized}
    end
  end
end
