defmodule CivicWeb.IncidentController do
  use CivicWeb, :controller

  alias Civic.Incidents

  action_fallback CivicWeb.FallbackController

  def create(conn, params) do
    with {:ok, key} <- idempotency_key(conn),
         {:ok, outcome, incident} <- Incidents.create_incident(params, key) do
      conn
      |> put_status(status_for(outcome))
      |> put_view(json: CivicWeb.IncidentJSON)
      |> render(:show, incident: incident)
    end
  end

  defp status_for(:created), do: :created
  defp status_for(:existing), do: :ok

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
