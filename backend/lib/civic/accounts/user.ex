defmodule Civic.Accounts.User do
  @moduledoc """
  Una cuenta. Guarda un alias y el hash de la contraseña; **no** guarda nombre,
  teléfono, correo, DNI ni IP. Los reportes y los votos no apuntan a esta tabla
  (ver `Civic.Privacy`).
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Civic.Accounts.Password

  # Letras sin tilde, números, guion, guion bajo y punto: sin espacios ni
  # caracteres de control, de dirección de texto ni parecidos a otros (homoglifos)
  @formato_alias ~r/\A[A-Za-z0-9_.-]{3,20}\z/

  @primary_key {:id, :binary_id, autogenerate: true}
  @timestamps_opts [type: :utc_datetime_usec]

  @type t :: %__MODULE__{}

  schema "usuarios" do
    field :alias, :string
    # `redact: true` evita que aparezcan en logs, inspect o errores
    field :password, :string, virtual: true, redact: true
    field :password_hash, :string, redact: true
    field :nivel, Ecto.Enum, values: [:invitado, :verificado], default: :invitado
    field :acepta_consentimiento, :boolean, virtual: true

    field :intentos_fallidos, :integer, default: 0
    field :ultimo_fallo_en, :utc_datetime_usec
    field :bloqueado_hasta, :utc_datetime_usec

    timestamps()
  end

  @doc "¿Tiene la forma de un alias válido? (para no consultar la base con basura)"
  @spec alias_valid?(term()) :: boolean()
  def alias_valid?(value), do: is_binary(value) and Regex.match?(@formato_alias, value)

  @doc """
  Datos de un registro. Solo se aceptan alias, contraseña y consentimiento: el
  nivel, los contadores y el id jamás los decide el cliente.

  El hash (caro de calcular) solo se calcula si todo lo demás es válido.
  """
  def registration_changeset(user, attrs) do
    user
    |> cast(attrs, [:alias, :password, :acepta_consentimiento])
    |> validate_required([:alias, :password, :acepta_consentimiento], message: "es obligatorio")
    |> update_change(:alias, &String.trim/1)
    |> update_change(:password, &Password.normalize/1)
    |> validate_alias()
    |> validate_acceptance(:acepta_consentimiento,
      message: "debes aceptar la política de privacidad"
    )
    |> validate_password()
    |> hash_password()
  end

  defp validate_alias(changeset) do
    changeset
    |> validate_length(:alias, min: 3, max: 20, message: "debe tener entre 3 y 20 caracteres")
    |> validate_format(:alias, @formato_alias,
      message: "solo puede tener letras sin tilde, números, guion, guion bajo y punto"
    )
    |> unique_constraint(:alias, name: :usuarios_alias_lower_index, message: "ya está en uso")
    |> check_constraint(:alias,
      name: :usuarios_alias_longitud,
      message: "debe tener entre 3 y 20 caracteres"
    )
  end

  defp validate_password(changeset) do
    alias_ = get_field(changeset, :alias)

    validate_change(changeset, :password, fn :password, password ->
      for message <- Password.errors(password, alias_), do: {:password, message}
    end)
  end

  defp hash_password(%Ecto.Changeset{valid?: true, changes: %{password: password}} = changeset) do
    changeset
    |> put_change(:password_hash, Password.hash(password))
    # La contraseña en claro no debe sobrevivir al changeset
    |> delete_change(:password)
  end

  defp hash_password(changeset), do: changeset
end
