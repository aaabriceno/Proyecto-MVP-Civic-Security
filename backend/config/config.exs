# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :civic,
  ecto_repos: [Civic.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true]

config :civic, Civic.Repo, types: Civic.PostgresTypes

# Configure the endpoint
config :civic, CivicWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: CivicWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Civic.PubSub,
  live_view: [signing_salt: "KwCyfTf6"]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Nunca escribir estos parámetros en los logs (se muestran como [FILTERED])
config :phoenix, :filter_parameters, ["password", "dni"]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
