defmodule CivicWeb.MapJSON do
  alias CivicWeb.IncidentJSON

  def snapshot(%{incidents: incidents}) do
    %{data: %{incidentes: Enum.map(incidents, &IncidentJSON.data/1)}}
  end
end
