defmodule CivicWeb.MapController do
  use CivicWeb, :controller

  alias Civic.Incidents
  alias Civic.Incidents.Bbox
  alias Civic.Incidents.Heat

  action_fallback CivicWeb.FallbackController

  # Ventana de tiempo del mapa en este avance (luego será 1 h / 24 h / 7 d)
  @ventana_horas 24

  def snapshot(conn, params) do
    with {:ok, bbox} <- Bbox.parse(params["bbox"]) do
      since = DateTime.add(DateTime.utc_now(), -@ventana_horas, :hour)

      conn
      |> put_view(json: CivicWeb.MapJSON)
      |> render(:snapshot, incidents: Incidents.list_recent(bbox, since))
    end
  end

  # Densidad por zona (mapa de calor): una consulta agregada, nunca incidentes
  # sueltos. Pública, igual que el mapa.
  def heat(conn, params) do
    with {:ok, bbox} <- Bbox.parse(params["bbox"]),
         {:ok, ventana} <- Heat.parse_window(params["ventana"]) do
      conn
      |> put_view(json: CivicWeb.MapJSON)
      |> render(:heat, heat: Heat.compute(bbox, ventana), ventana: ventana)
    end
  end
end
