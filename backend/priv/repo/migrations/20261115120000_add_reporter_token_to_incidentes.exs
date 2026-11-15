defmodule Civic.Repo.Migrations.AddReporterTokenToIncidentes do
  use Ecto.Migration

  # HMAC(k_rep, cuenta ‖ incidente): sirve para reconocer al autor de ESTE
  # incidente (por ejemplo, impedir que vote su propio reporte) sin guardar quién
  # es. Cambia en cada incidente, así que dos reportes de una misma persona no se
  # pueden enlazar. Es nulo en los incidentes sin cuenta (siembra de desarrollo).
  def change do
    alter table(:incidentes) do
      add :reporter_token, :binary
    end
  end
end
