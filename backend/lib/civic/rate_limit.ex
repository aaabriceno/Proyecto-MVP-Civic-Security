defmodule Civic.RateLimit do
  @moduledoc """
  Limitador de tasa en memoria (ETS). Los contadores viven solo en RAM y se
  descartan solos: no se guarda ninguna IP en disco ni en la base de datos.

  Los límites se definen por "cubeta" (`:write`, `:read`, `:socket`) en
  `config :civic, CivicWeb.RateLimit` como `{máximo, ventana_en_ms}`.
  """

  use Hammer, backend: :ets

  @doc "Límite `{máximo, ventana_ms}` configurado para la cubeta."
  def limits(bucket) do
    :civic |> Application.fetch_env!(CivicWeb.RateLimit) |> Keyword.fetch!(bucket)
  end

  @doc """
  Cuenta una solicitud de `client` en la cubeta. Devuelve `:ok` o
  `{:deny, milisegundos_para_reintentar}`.
  """
  def check(bucket, client) do
    {limit, scale} = limits(bucket)

    case hit({bucket, client}, scale, limit) do
      {:allow, _count} -> :ok
      {:deny, retry_ms} -> {:deny, retry_ms}
    end
  end
end
