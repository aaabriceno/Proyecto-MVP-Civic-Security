defmodule CivicWeb.Router do
  use CivicWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", CivicWeb do
    pipe_through :api

    get "/health", HealthController, :show
  end

  scope "/api", CivicWeb do
    pipe_through :api
  end
end
