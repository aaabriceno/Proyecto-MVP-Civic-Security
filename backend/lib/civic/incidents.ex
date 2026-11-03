defmodule Civic.Incidents do
  @moduledoc """
  Contexto de incidentes: crear y consultar reportes anónimos.
  """

  import Ecto.Query

  alias Civic.Repo
  alias Civic.Incidents.Incident

  @max_resultados 500

  def create_incident(attrs, idempotency_key) do
    case Repo.get_by(Incident, idempotency_key: idempotency_key) do
      %Incident{} = existente -> {:ok, :existing, existente}
      nil -> insertar(attrs, idempotency_key)
    end
  end

  @doc """
  Incidentes creados después de `since` que caen dentro del `bbox`
  (`{min_lng, min_lat, max_lng, max_lat}`), del más nuevo al más antiguo.
  Devuelve como máximo 500.
  """
  def list_recent({min_lng, min_lat, max_lng, max_lat}, %DateTime{} = since) do
    Incident
    |> where([i], i.inserted_at > ^since)
    |> where(
      [i],
      fragment(
        "ST_Intersects(?, ST_MakeEnvelope(?, ?, ?, ?, 4326)::geography)",
        i.ubicacion,
        ^min_lng,
        ^min_lat,
        ^max_lng,
        ^max_lat
      )
    )
    |> order_by([i], desc: i.inserted_at)
    |> limit(^@max_resultados)
    |> Repo.all()
  end

  defp insertar(attrs, idempotency_key) do
    %Incident{idempotency_key: idempotency_key}
    |> Incident.create_changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, incident} -> {:ok, :created, incident}
      {:error, changeset} -> manejar_error(changeset, idempotency_key)
    end
  end

  # Si otra petición con la misma key ganó la carrera, devolvemos la suya
  defp manejar_error(changeset, idempotency_key) do
    if Keyword.has_key?(changeset.errors, :idempotency_key) do
      {:ok, :existing, Repo.get_by!(Incident, idempotency_key: idempotency_key)}
    else
      {:error, changeset}
    end
  end
end
