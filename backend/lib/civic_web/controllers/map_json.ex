defmodule CivicWeb.MapJSON do
  alias CivicWeb.IncidentJSON

  def snapshot(%{incidents: incidents}) do
    %{data: %{incidentes: Enum.map(incidents, &IncidentJSON.data/1)}}
  end

  @etiquetas %{hora: "1h", dia: "24h", semana: "7d"}

  def heat(%{heat: %{cell_deg: cell_deg, cells: cells}, ventana: ventana}) do
    %{
      data: %{
        ventana: Map.fetch!(@etiquetas, ventana),
        cell_deg: cell_deg,
        # La celda más activa: la app lo usa para escalar los colores
        max: cells |> Enum.map(& &1.count) |> Enum.max(fn -> 0 end),
        celdas: Enum.map(cells, &celda/1)
      }
    }
  end

  defp celda(%{lat: lat, lng: lng, count: count, tipos: tipos, franja: {desde, hasta}}) do
    %{lat: lat, lng: lng, count: count, tipos: tipos, franja: %{desde: desde, hasta: hasta}}
  end
end
