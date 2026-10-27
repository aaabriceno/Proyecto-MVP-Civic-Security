defmodule Civic.Repo do
  use Ecto.Repo,
    otp_app: :civic,
    adapter: Ecto.Adapters.Postgres
end
