defmodule Civic.Incidents do
  @moduledoc """
  Contexto de incidentes: crear y consultar reportes anónimos.
  """

  alias Civic.Repo
  alias Civic.Incidents.Incident

  def create_incident(attrs, idempotency_key) do
    case Repo.get_by(Incident, idempotency_key: idempotency_key) do
      %Incident{} = existente -> {:ok, :existing, existente}
      nil -> insertar(attrs, idempotency_key)
    end
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
