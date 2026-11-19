defmodule CivicWeb.VoteController do
  @moduledoc """
  Validación comunitaria: confirmar o negar el reporte de otra persona (ruta
  protegida por `Plugs.Authenticate`). Las reglas viven en `Civic.Validation`.

  La ubicación de quien vota llega en el cuerpo, se usa para comprobar que está
  cerca del lugar y se descarta: no se guarda ni se devuelve.
  """

  use CivicWeb, :controller

  alias Civic.Accounts
  alias Civic.Accounts.User
  alias Civic.Validation

  action_fallback CivicWeb.FallbackController

  @doc "Registra el voto y devuelve el reporte con sus contadores y estado nuevos."
  def create(conn, %{"id" => id} = params) do
    with {:ok, user} <- current_user(conn),
         {:ok, incident} <-
           Validation.vote(user, id, params["valor"], params["lat"], params["lng"]) do
      broadcast_update(incident)

      conn
      |> put_status(:created)
      |> put_view(json: CivicWeb.IncidentJSON)
      |> render(:show, incident: incident)
    end
  end

  # Para que los demás mapas abiertos vean el reporte con sus votos y su estado.
  # Es el mismo incidente (mismo id): la app lo reemplaza.
  defp broadcast_update(incident) do
    CivicWeb.Endpoint.broadcast!(
      "mapa:arequipa",
      "incidente_actualizado",
      CivicWeb.IncidentJSON.data(incident)
    )
  end

  # El access token puede seguir vigente (15 min) aunque la cuenta ya se haya borrado
  defp current_user(conn) do
    case Accounts.get_user(conn.assigns.current_user_id) do
      %User{} = user -> {:ok, user}
      nil -> {:error, :unauthorized}
    end
  end
end
