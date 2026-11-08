defmodule Civic.Accounts.RefreshToken do
  @moduledoc """
  Una sesión renovable. Guarda el SHA-256 del token, nunca el token, y solo
  fechas de día (sin hora). No guarda IP, dispositivo ni navegador.
  """

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "refresh_tokens" do
    field :usuario_id, :binary_id
    field :token_hash, :binary, redact: true
    field :familia, :binary_id
    field :creado_en, :date
    field :expira_en, :date
    field :revocado_en, :date
  end
end
