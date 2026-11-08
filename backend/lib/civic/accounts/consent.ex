defmodule Civic.Accounts.Consent do
  @moduledoc """
  Evidencia de que una persona aceptó la política de privacidad, con la versión
  del texto que aceptó (Ley N.º 29733). Se borra junto con la cuenta.
  """

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "consentimientos" do
    belongs_to :usuario, Civic.Accounts.User
    field :version, :string
    field :aceptado_en, :utc_datetime_usec
  end
end
