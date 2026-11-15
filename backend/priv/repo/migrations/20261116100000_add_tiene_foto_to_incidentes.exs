defmodule Civic.Repo.Migrations.AddTieneFotoToIncidentes do
  use Ecto.Migration

  # Solo la marca "tiene foto"; el archivo vive aparte (Civic.Evidence.Store). Es un
  # booleano y no una fecha a propósito: la hora en que se subió la foto, junto a
  # la del reporte, ayudaría a reconocer quién la tomó.
  def change do
    alter table(:incidentes) do
      add :tiene_foto, :boolean, null: false, default: false
    end
  end
end
