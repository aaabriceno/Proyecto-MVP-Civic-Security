defmodule Civic.Repo.Migrations.CreateUsuarios do
  use Ecto.Migration

  def change do
    # Una cuenta NO guarda nombre, teléfono, correo, DNI ni IP. Solo un alias
    # elegido por la persona y el hash de su contraseña.
    create table(:usuarios, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :alias, :string, size: 20, null: false
      # Argon2id. NULL para las cuentas de invitado (no tienen contraseña).
      add :password_hash, :string
      add :nivel, :string, null: false, default: "invitado"

      # Protección contra fuerza bruta (ver Civic.Accounts.authenticate/3)
      add :intentos_fallidos, :integer, null: false, default: 0
      add :ultimo_fallo_en, :utc_datetime_usec
      add :bloqueado_hasta, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    # El alias es único sin distinguir mayúsculas ("Halcon" = "halcon")
    create unique_index(:usuarios, ["lower(alias)"], name: :usuarios_alias_lower_index)

    # Defensa en profundidad: aunque falle la validación de la aplicación, la
    # base rechaza estos valores
    create constraint(:usuarios, :usuarios_alias_longitud,
             check: "char_length(alias) BETWEEN 3 AND 20"
           )

    create constraint(:usuarios, :usuarios_nivel_valido,
             check: "nivel IN ('invitado', 'verificado')"
           )

    # Evidencia de que la persona aceptó la política de privacidad (Ley 29733).
    # Se borra junto con la cuenta.
    create table(:consentimientos, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :usuario_id, references(:usuarios, type: :binary_id, on_delete: :delete_all),
        null: false

      add :version, :string, null: false
      add :aceptado_en, :utc_datetime_usec, null: false
    end

    create index(:consentimientos, [:usuario_id])
  end
end
