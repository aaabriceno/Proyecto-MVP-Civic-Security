defmodule CivicWeb.Router do
  use CivicWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Límites por cliente (ver Civic.RateLimit). Escribir es más caro que leer.
  pipeline :limit_write do
    plug CivicWeb.Plugs.RateLimit, bucket: :write
  end

  pipeline :limit_read do
    plug CivicWeb.Plugs.RateLimit, bucket: :read
  end

  # Cuentas: cada acción tiene su propio contador por IP
  pipeline :limit_register do
    plug CivicWeb.Plugs.RateLimit, bucket: :register
  end

  pipeline :limit_login do
    plug CivicWeb.Plugs.RateLimit, bucket: :login
  end

  pipeline :limit_refresh do
    plug CivicWeb.Plugs.RateLimit, bucket: :refresh
  end

  # Registro e inicio de sesión calculan Argon2id: además del límite por IP
  # tienen un tope global de peticiones simultáneas (Civic.HashGate)
  pipeline :hash_gate do
    plug CivicWeb.Plugs.HashGate
  end

  # Rutas que exigen un access token válido
  pipeline :authenticate do
    plug CivicWeb.Plugs.Authenticate
  end

  scope "/", CivicWeb do
    pipe_through [:api, :limit_read]

    get "/health", HealthController, :show
  end

  scope "/v1/auth", CivicWeb do
    pipe_through [:api, :limit_register, :hash_gate]
    post "/register", AuthController, :register
  end

  scope "/v1/auth", CivicWeb do
    pipe_through [:api, :limit_login, :hash_gate]
    post "/login", AuthController, :login
  end

  scope "/v1/auth", CivicWeb do
    pipe_through [:api, :limit_refresh]
    post "/refresh", AuthController, :refresh
    post "/logout", AuthController, :logout
  end

  scope "/v1", CivicWeb do
    pipe_through [:api, :limit_write]

    post "/incidents", IncidentController, :create
  end

  scope "/v1", CivicWeb do
    pipe_through [:api, :limit_read]

    get "/map/snapshot", MapController, :snapshot
  end

  scope "/v1", CivicWeb do
    pipe_through [:api, :limit_read, :authenticate]

    get "/me", MeController, :show
  end
end
