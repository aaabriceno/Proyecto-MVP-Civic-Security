defmodule Civic.Repo.Migrations.CreateIncidentes do
  use Ecto.Migration

  def up do
    execute "CREATE EXTENSION IF NOT EXISTS postgis"

    create table(:incidentes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :tipo, :string, null: false
      add :descripcion, :string, size: 500
      add :ubicacion, :"geography(Point,4326)", null: false
      add :estado, :string, null: false, default: "sin_verificar"
      add :idempotency_key, :binary_id, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:incidentes, [:idempotency_key])
    create index(:incidentes, [:ubicacion], using: :gist)
    create index(:incidentes, [:inserted_at])
  end

  def down do
    drop table(:incidentes)
  end
end
