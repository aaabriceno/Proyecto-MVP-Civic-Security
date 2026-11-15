defmodule CivicWeb.IncidentController do
  use CivicWeb, :controller

  alias Civic.Accounts
  alias Civic.Accounts.User
  alias Civic.Incidents

  action_fallback CivicWeb.FallbackController

  def create(conn, params) do
    with {:ok, user} <- current_user(conn),
         {:ok, key} <- idempotency_key(conn),
         {:ok, outcome, incident} <- Incidents.report_incident(user, params, key) do
      if outcome == :created, do: broadcast_new(incident)

      conn
      |> put_status(status_for(outcome))
      |> put_view(json: CivicWeb.IncidentJSON)
      |> render(:show, incident: incident)
    end
  end

  # Se emite desde la capa web para que el dominio (Civic.*) no dependa de ella.
  # Solo para reportes nuevos: repetir la idempotency-key no vuelve a emitir.
  defp broadcast_new(incident) do
    CivicWeb.Endpoint.broadcast!(
      "mapa:arequipa",
      "incidente_nuevo",
      CivicWeb.IncidentJSON.data(incident)
    )
  end

  defp status_for(:created), do: :created
  defp status_for(:existing), do: :ok

  # El access token puede seguir vigente (15 min) aunque la cuenta ya se haya
  # borrado: en ese caso es un 401, como en /me.
  defp current_user(conn) do
    case Accounts.get_user(conn.assigns.current_user_id) do
      %User{} = user -> {:ok, user}
      nil -> {:error, :unauthorized}
    end
  end

  # El encabezado debe existir y ser un UUID válido
  defp idempotency_key(conn) do
    with [value | _] <- get_req_header(conn, "idempotency-key"),
         {:ok, uuid} <- Ecto.UUID.cast(value) do
      {:ok, uuid}
    else
      _ -> {:error, :idempotency_key_required}
    end
  end
end
