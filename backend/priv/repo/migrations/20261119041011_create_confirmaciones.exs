defmodule Civic.Repo.Migrations.CreateConfirmaciones do
  use Ecto.Migration

  def change do
    # Validación comunitaria. Un voto es "lo confirmo" o "es falso" sobre un
    # reporte. NO guarda quién votó: solo `voter_token = HMAC(k_vote, cuenta ‖
    # incidente)` (ver Civic.Privacy), que sirve para que una cuenta vote una sola
    # vez sin saber de quién es el voto. Tampoco guarda la ubicación del votante:
    # se usa solo para comprobar que estaba cerca y se descarta.
    create table(:confirmaciones, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :incidente_id, references(:incidentes, type: :binary_id, on_delete: :delete_all),
        null: false

      add :valor, :string, null: false
      add :voter_token, :binary, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    # Un voto por cuenta y reporte, sin saber de quién es
    create unique_index(:confirmaciones, [:incidente_id, :voter_token])

    # Defensa en profundidad: el token mide 32 bytes (SHA-256) y el valor es uno de los dos
    create constraint(:confirmaciones, :confirmaciones_token_valido,
             check: "octet_length(voter_token) = 32"
           )

    create constraint(:confirmaciones, :confirmaciones_valor_valido,
             check: "valor IN ('confirmo', 'falso')"
           )

    # Contadores públicos del reporte (cuántas cuentas lo confirman / lo niegan).
    # No dicen quién votó. El estado cambia cuando uno llega al umbral.
    alter table(:incidentes) do
      add :confirmaciones, :integer, null: false, default: 0
      add :falsos, :integer, null: false, default: 0
    end

    create constraint(:incidentes, :incidentes_votos_no_negativos,
             check: "confirmaciones >= 0 AND falsos >= 0"
           )
  end
end
