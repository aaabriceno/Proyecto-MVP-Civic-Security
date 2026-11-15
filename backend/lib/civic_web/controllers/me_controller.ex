defmodule CivicWeb.MeController do
  @moduledoc """
  La cuenta de quien hace la petición (rutas protegidas por `Plugs.Authenticate`):
  ver el perfil, cambiar la contraseña y borrar la cuenta.
  """

  use CivicWeb, :controller

  alias Civic.Accounts
  alias Civic.Accounts.Sessions
  alias Civic.Accounts.User
  alias Civic.Incidents.Quota

  action_fallback CivicWeb.FallbackController

  def show(conn, _params) do
    with {:ok, user} <- current_user(conn) do
      conn
      |> put_view(json: CivicWeb.AuthJSON)
      |> render(:me, user: user, cupo: Quota.usage(user))
    end
  end

  @doc """
  Cambia la contraseña y cierra todas las demás sesiones. Devuelve una sesión
  nueva para el dispositivo que la cambió.
  """
  def update_password(conn, params) do
    with {:ok, user} <- current_user(conn),
         {:ok, user} <-
           user
           |> Accounts.change_password(params["current_password"], params["new_password"])
           |> field_errors(wrong: :current_password, rename: {:password, :new_password}),
         :ok <- Sessions.revoke_all(user),
         {:ok, tokens} <- Sessions.issue(user) do
      conn
      |> put_view(json: CivicWeb.AuthJSON)
      |> render(:session, user: user, tokens: tokens)
    end
  end

  @doc """
  Borra la cuenta (pide la contraseña). Sus reportes se conservan, sin ningún
  vínculo con ella.
  """
  def delete(conn, params) do
    with {:ok, user} <- current_user(conn),
         {:ok, _} <-
           user |> Accounts.delete_account(params["password"]) |> field_errors(wrong: :password) do
      send_resp(conn, :no_content, "")
    end
  end

  # El token puede seguir vigente (15 min) aunque la cuenta ya se haya borrado
  defp current_user(conn) do
    case Accounts.get_user(conn.assigns.current_user_id) do
      %User{} = user -> {:ok, user}
      nil -> {:error, :unauthorized}
    end
  end

  # Una contraseña equivocada NO es un 401: la sesión está bien y la app la
  # tomaría por vencida (renovaría y repetiría, y cada toque contaría como dos
  # intentos fallidos). Se responde como error del campo, igual que cualquier
  # otro dato inválido de un formulario.
  defp field_errors({:error, :invalid_credentials}, opts),
    do: {:error, {:invalid_field, Keyword.fetch!(opts, :wrong)}}

  defp field_errors({:error, %Ecto.Changeset{} = changeset}, opts) do
    case Keyword.get(opts, :rename) do
      {from, to} ->
        errors =
          for {field, error} <- changeset.errors,
              do: {if(field == from, do: to, else: field), error}

        {:error, %{changeset | errors: errors}}

      nil ->
        {:error, changeset}
    end
  end

  defp field_errors(other, _opts), do: other
end
