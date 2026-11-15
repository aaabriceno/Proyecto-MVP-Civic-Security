defmodule Civic.Repo.Migrations.AddVerifHashToUsuarios do
  use Ecto.Migration

  def change do
    # Verificación por DNI. NUNCA se guarda el DNI: solo `HMAC(k_verif, DNI)`, de
    # un solo sentido (ver Civic.Privacy). Sirve para una cosa: saber si ese número
    # ya tiene una cuenta ("una persona = una cuenta").
    alter table(:usuarios) do
      add :verif_hash, :binary
      # Versión de la clave con la que se calculó, para poder rotarla
      add :verif_version, :integer
    end

    # Un DNI, una cuenta. Los NULL (cuentas sin verificar) no chocan entre sí.
    create unique_index(:usuarios, [:verif_hash], name: :usuarios_verif_hash_index)

    # Defensa en profundidad: hash y versión van juntos, y el hash mide 32 bytes
    # (SHA-256). Así no se puede guardar un DNI en claro en esta columna por error.
    create constraint(:usuarios, :usuarios_verif_hash_valido,
             check:
               "(verif_hash IS NULL AND verif_version IS NULL) OR " <>
                 "(octet_length(verif_hash) = 32 AND verif_version > 0)"
           )
  end
end
