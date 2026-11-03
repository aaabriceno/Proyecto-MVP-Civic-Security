defmodule Civic.Incidents do
  @moduledoc """
  Contexto de incidentes: crear y consultar reportes anónimos.
  """

  import Ecto.Query

  alias Civic.Repo
  alias Civic.Incidents.Incident

  @max_resultados 500

  @doc """
  Crea un incidente. `idempotency_key` evita duplicados cuando la app reintenta
  el envío:

    * clave nueva -> `{:ok, :created, incidente}`
    * clave repetida con el **mismo** contenido -> `{:ok, :existing, incidente}`
    * clave repetida con **otro** contenido -> `{:error, :idempotency_conflict}`
      (si no, el reporte nuevo se perdería en silencio)
  """
  def create_incident(attrs, idempotency_key) do
    case Repo.get_by(Incident, idempotency_key: idempotency_key) do
      %Incident{} = existente -> replay(existente, attrs)
      nil -> insertar(attrs, idempotency_key)
    end
  end

  defp replay(existente, attrs) do
    changeset = Incident.create_changeset(%Incident{}, attrs)

    cond do
      not changeset.valid? -> {:error, %{changeset | action: :insert}}
      Incident.same_content?(existente, changeset) -> {:ok, :existing, existente}
      true -> {:error, :idempotency_conflict}
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
      {:error, changeset} -> manejar_error(changeset, attrs, idempotency_key)
    end
  end

  # Si otra petición con la misma key ganó la carrera, se trata como repetición
  defp manejar_error(changeset, attrs, idempotency_key) do
    if Keyword.has_key?(changeset.errors, :idempotency_key) do
      replay(Repo.get_by!(Incident, idempotency_key: idempotency_key), attrs)
    else
      {:error, changeset}
    end
  end
end
