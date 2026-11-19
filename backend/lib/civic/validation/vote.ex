defmodule Civic.Validation.Vote do
  @moduledoc """
  Un voto de la comunidad sobre un reporte: "lo confirmo" o "es falso".

  No tiene id de cuenta ni ubicación: solo `voter_token`, el
  `HMAC(k_vote, cuenta ‖ incidente)` de `Civic.Privacy`. Así una cuenta no puede
  votar dos veces el mismo reporte, pero nadie ve de quién es cada voto.
  """

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "confirmaciones" do
    field :incidente_id, :binary_id
    field :valor, Ecto.Enum, values: [:confirmo, :falso]
    field :voter_token, :binary, redact: true

    timestamps()
  end
end
