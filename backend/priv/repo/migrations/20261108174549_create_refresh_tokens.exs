defmodule Civic.Repo.Migrations.CreateRefreshTokens do
  use Ecto.Migration

  def change do
    # Sesiones: un refresh token por fila. Se guarda solo su SHA-256, nunca el
    # token. Las fechas son DÍAS, sin hora: así la tabla no sirve para
    # sospechar de quién estaba conectado cuando se creó un reporte.
    # Tampoco hay IP, dispositivo ni navegador.
    create table(:refresh_tokens, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :usuario_id, references(:usuarios, type: :binary_id, on_delete: :delete_all),
        null: false

      add :token_hash, :binary, null: false
      # Todos los tokens que nacen de un mismo inicio de sesión comparten familia
      add :familia, :binary_id, null: false
      add :creado_en, :date, null: false
      add :expira_en, :date, null: false
      # Se llena al usarse (rotación) o al revocarse (cierre de sesión, reuso)
      add :revocado_en, :date
    end

    create unique_index(:refresh_tokens, [:token_hash])
    create index(:refresh_tokens, [:usuario_id])
    create index(:refresh_tokens, [:familia])
  end
end
