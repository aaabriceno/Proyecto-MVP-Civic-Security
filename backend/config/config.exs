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

# Límites por cliente: {máximo de solicitudes, ventana en ms}. Sin cuentas aún,
# el cliente es su IP, y muchos alumnos tras el wifi de la universidad
# comparten una: por eso estos valores son GENEROSOS (solo frenan inundaciones
# masivas). El límite estricto irá por cuenta cuando exista la autenticación.
config :civic, CivicWeb.RateLimit,
  write: {120, :timer.minutes(10)},
  read: {600, :timer.minutes(1)},
  socket: {120, :timer.minutes(1)}

# Argon2id para las contraseñas (type 2 = argon2id). m_cost es el exponente de
# KiB: 15 -> 2^15 KiB = 32 MiB. Con t=3 y p=1 supera el mínimo de OWASP
# (19 MiB, t=2, p=1). Subirlo hace cada intento de adivinar más caro para un
# atacante, pero también consume más memoria por inicio de sesión.
config :argon2_elixir, argon2_type: 2, t_cost: 3, m_cost: 15, parallelism: 1

# Versión de clave vigente para cada propósito de Civic.Privacy. Las claves en sí
# NO van aquí: en dev/test se derivan en su archivo y en producción vienen de
# variables de entorno (config/runtime.exs).
config :civic, Civic.Privacy, current: %{verif: 1, rep: 1, vote: 1}

import_config "#{config_env()}.exs"
