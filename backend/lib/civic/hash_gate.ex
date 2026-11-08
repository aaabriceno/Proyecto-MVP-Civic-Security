defmodule Civic.HashGate do
  @moduledoc """
  Semáforo que limita cuántos registros e inicios de sesión se atienden a la
  vez. Pasado el tope, los demás reciben `:busy` al instante (en la web, un 503
  con `retry-after`) en vez de quedarse en cola.

  Para qué sirve: calcular Argon2id es caro a propósito (~32 MiB y decenas de
  milisegundos por intento). Argon2 corre en los *dirty schedulers* de la BEAM,
  que ya limitan cuántos hashes se calculan a la vez (uno por núcleo), así que
  la memoria no se dispara. Lo que sí pasaría ante una avalancha es que miles de
  solicitudes formen una cola larga: cada persona legítima esperaría detrás de
  todas y la respuesta tardaría segundos o minutos. Con el tope, la cola es corta
  y lo que sobra se rechaza rápido.

  Cada cupo pertenece a un proceso y el semáforo lo vigila: si el proceso muere
  sin devolverlo, el cupo se recupera solo.

  El máximo se lee de `config :civic, Civic.HashGate, max_concurrent: n` en cada
  petición, como hace `Civic.RateLimit` con sus límites.
  """

  use GenServer

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc """
  Pide un cupo en el semáforo de la aplicación para el proceso actual (o para
  `pid`). Devuelve `:ok` o `:busy`. Pedirlo dos veces no gasta dos cupos.
  """
  def acquire, do: acquire(__MODULE__, self())
  def acquire(pid) when is_pid(pid), do: acquire(__MODULE__, pid)
  def acquire(server, pid), do: GenServer.call(server, {:acquire, pid})

  @doc "Devuelve el cupo. Si el proceso no tenía ninguno, no hace nada."
  def release, do: release(__MODULE__, self())
  def release(pid) when is_pid(pid), do: release(__MODULE__, pid)
  def release(server, pid), do: GenServer.cast(server, {:release, pid})

  @doc "Cuántos cupos están ocupados."
  def in_use, do: in_use(__MODULE__)
  def in_use(server), do: GenServer.call(server, :in_use)

  # --- servidor ---

  @impl true
  def init(:ok), do: {:ok, %{}}

  # El estado es %{pid => referencia_del_monitor}
  @impl true
  def handle_call({:acquire, pid}, _from, holders) do
    cond do
      Map.has_key?(holders, pid) ->
        {:reply, :ok, holders}

      map_size(holders) >= max_concurrent() ->
        {:reply, :busy, holders}

      true ->
        {:reply, :ok, Map.put(holders, pid, Process.monitor(pid))}
    end
  end

  def handle_call(:in_use, _from, holders), do: {:reply, map_size(holders), holders}

  @impl true
  def handle_cast({:release, pid}, holders) do
    {:noreply, drop(holders, pid)}
  end

  # El proceso murió sin devolver el cupo
  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, holders) do
    {:noreply, Map.delete(holders, pid)}
  end

  defp drop(holders, pid) do
    case Map.pop(holders, pid) do
      {nil, holders} ->
        holders

      {ref, holders} ->
        Process.demonitor(ref, [:flush])
        holders
    end
  end

  defp max_concurrent do
    :civic |> Application.fetch_env!(__MODULE__) |> Keyword.fetch!(:max_concurrent)
  end
end
