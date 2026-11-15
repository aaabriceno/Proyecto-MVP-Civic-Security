defmodule Civic.Incidents.Quota do
  @moduledoc """
  Cupo diario de reportes nuevos por cuenta.

  Una cuenta sin verificar reporta poco; una verificada, más. El conteo vive solo
  en la memoria del servidor (ETS, vía `Civic.RateLimit`): no se escribe en la
  base de datos, así que no queda registro de cuántos reportes hizo cada persona
  y se reinicia al reiniciar el servidor.

  La clave del contador es solo el id de la cuenta, no el nivel: si una cuenta se
  verifica a mitad del día conserva lo gastado y pasa a tener el cupo mayor.

  Los límites `{máximo, ventana_ms}` se leen de
  `config :civic, Civic.Incidents.Quota`.
  """

  alias Civic.Accounts.User
  alias Civic.RateLimit

  @doc """
  Gasta una unidad del cupo de la cuenta. Devuelve `:ok` o
  `{:error, {:quota_exceeded, milisegundos_para_reintentar}}`.
  """
  @spec consume(User.t()) :: :ok | {:error, {:quota_exceeded, pos_integer()}}
  def consume(%User{id: id, nivel: nivel}) do
    {max, ventana_ms} = limit(nivel)

    case RateLimit.hit({:report_quota, id}, ventana_ms, max) do
      {:allow, _usados} -> :ok
      {:deny, retry_ms} -> {:error, {:quota_exceeded, retry_ms}}
    end
  end

  @doc """
  Cuánto lleva gastado la cuenta y cuánto le corresponde, sin gastar nada. Los
  intentos pasados del máximo (que se rechazaron) no se cuentan.
  """
  @spec usage(User.t()) :: %{usados: non_neg_integer(), maximo: pos_integer()}
  def usage(%User{id: id, nivel: nivel}) do
    {max, ventana_ms} = limit(nivel)
    %{usados: min(RateLimit.get({:report_quota, id}, ventana_ms), max), maximo: max}
  end

  @doc "Límite `{máximo, ventana_ms}` del nivel de cuenta."
  @spec limit(atom()) :: {pos_integer(), pos_integer()}
  def limit(nivel) do
    :civic
    |> Application.fetch_env!(__MODULE__)
    |> Keyword.fetch!(cupo(nivel))
  end

  # `:invitado` es el nombre actual de "cuenta sin verificar"
  defp cupo(:verificado), do: :verificado
  defp cupo(_sin_verificar), do: :sin_verificar
end
