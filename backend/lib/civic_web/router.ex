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

  scope "/", CivicWeb do
    pipe_through [:api, :limit_read]

    get "/health", HealthController, :show
  end

  scope "/v1", CivicWeb do
    pipe_through [:api, :limit_write]

    post "/incidents", IncidentController, :create
  end

  scope "/v1", CivicWeb do
    pipe_through [:api, :limit_read]

    get "/map/snapshot", MapController, :snapshot
  end
end
