import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :civic, Civic.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "civic_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :civic, CivicWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "bxfDNAGOuXkORvspIAJtyatxPCNiMozF+o6mnyneD+7e9VBAyYYTkJ5JKL4/BIiN",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# Argon2 barato SOLO en pruebas (si no, cada test tardaría ~100 ms). El
# formato del hash es el mismo; los valores reales están en config.exs.
config :argon2_elixir, t_cost: 1, m_cost: 8

# Claves de PRUEBA de Civic.Privacy (derivadas, sin secretos en el repo)
config :civic, Civic.Privacy,
  keys: %{
    {:verif, 1} => :crypto.hash(:sha256, "civic-test:verif:v1"),
    {:rep, 1} => :crypto.hash(:sha256, "civic-test:rep:v1"),
    {:vote, 1} => :crypto.hash(:sha256, "civic-test:vote:v1")
  }

# Tope muy alto: solo los tests del semáforo lo reducen a propósito
config :civic, Civic.HashGate, max_concurrent: 1_000

# Límites muy altos: solo los tests de rate limiting los reducen a propósito
config :civic, CivicWeb.RateLimit,
  write: {100_000, :timer.minutes(1)},
  read: {100_000, :timer.minutes(1)},
  socket: {100_000, :timer.minutes(1)},
  register: {100_000, :timer.minutes(1)},
  login: {100_000, :timer.minutes(1)},
  refresh: {100_000, :timer.minutes(1)}
