defmodule CivicWeb.IncidentJSON do
  @moduledoc """
  Serialización única de un incidente hacia la API.

  Solo expone los campos públicos: nunca `ubicacion` (formato interno de
  PostGIS) ni `idempotency_key`.
  """

  alias Civic.Incidents.Incident

  def data(%Incident{} = incident) do
    {lat, lng} = Incident.coords(incident)

    %{
      id: incident.id,
      tipo: incident.tipo,
      descripcion: incident.descripcion,
      lat: lat,
      lng: lng,
      estado: incident.estado,
      creado_en: incident.inserted_at
    }
  end

  def show(%{incident: incident}), do: %{data: data(incident)}
end
