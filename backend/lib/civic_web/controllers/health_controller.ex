defmodule CivicWeb.HealthController do
  use CivicWeb, :controller

  def show(conn, _params) do
    case Ecto.Adapters.SQL.query(Civic.Repo, "SELECT 1", []) do
      {:ok, _result} ->
        json(conn, %{status: "ok"})

      {:error, _reason} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{status: "db_down"})
    end
  end
end
