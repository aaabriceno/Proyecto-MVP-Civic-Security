defmodule CivicWeb.VerificationController do
  @moduledoc """
  Verificación de la cuenta por DNI (ruta protegida por `Plugs.Authenticate`).

  El DNI llega en el cuerpo, se convierte en una huella irreversible
  (`Civic.Accounts.Verification`) y se descarta: no se guarda, no se devuelve y
  Phoenix lo oculta de los logs.
  """

  use CivicWeb, :controller

  alias Civic.Accounts
  alias Civic.Accounts.{User, Verification}
  alias Civic.Incidents.Quota

  action_fallback CivicWeb.FallbackController

  @doc "Verifica la cuenta y devuelve su perfil (ahora con el cupo de una cuenta verificada)."
  def dni(conn, params) do
    with {:ok, user} <- current_user(conn),
         {:ok, user} <- Verification.verify_dni(user, params["dni"]) do
      conn
      |> put_view(json: CivicWeb.AuthJSON)
      |> render(:me, user: user, cupo: Quota.usage(user))
    end
  end

  # El token puede seguir vigente (15 min) aunque la cuenta ya se haya borrado
  defp current_user(conn) do
    case Accounts.get_user(conn.assigns.current_user_id) do
      %User{} = user -> {:ok, user}
      nil -> {:error, :unauthorized}
    end
  end
end
