defmodule Civic.Accounts.RefreshReplay do
  @moduledoc """
  Memoria de corta vida que permite **repetir** un refresh cuya respuesta se
  perdió por el camino.

  Cuando el servidor rota un refresh token, el teléfono puede no enterarse (se
  cae la señal justo en ese momento). Su reintento llegaría con un token que el
  servidor ya dio por usado y, sin esta memoria, se tomaría por un robo y se
  cerraría toda la sesión. Aquí se recuerda "este token usado produjo este token
  nuevo" durante unos segundos, para devolver el mismo resultado en vez de
  revocar: es la misma idea de idempotencia que `idempotency-key` en los
  reportes.

  Vive **solo en la memoria RAM del servidor**, nunca en disco:

    * en la base solo se guardan hashes y fechas de día, y el token nuevo en
      claro no puede salir de un hash;
    * una hora exacta de uso en la base permitiría relacionar quién estaba
      conectado con cuándo se hizo un reporte.

  Si el servidor se reinicia dentro de la ventana, se pierde lo recordado y el
  reintento se trata con el rigor de siempre (se revoca la familia). Lo mismo si
  se llena el tope de entradas: el fallo siempre cae hacia el lado estricto.

  La configuración (`config :civic, Civic.Accounts.RefreshReplay`) se lee en cada
  llamada: `ttl_seconds` (la ventana), `max_entries` y `sweep_every` (cada
  cuántos ms se limpia lo vencido, o `:never`).
  """

  use GenServer

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc """
  Recuerda `value` bajo `key` durante la ventana, contada desde `now_ms`.
  Devuelve `:full` (y no recuerda nada) si se alcanzó el tope de entradas.
  """
  def remember(key, value, now_ms), do: remember(__MODULE__, key, value, now_ms)

  def remember(server, key, value, now_ms),
    do: call(server, {:remember, key, value, now_ms}, :full)

  @doc """
  El valor recordado bajo `key` si la ventana sigue abierta en `now_ms`. Consultar
  no la alarga.
  """
  def lookup(key, now_ms), do: lookup(__MODULE__, key, now_ms)

  def lookup(server, key, now_ms), do: call(server, {:lookup, key, now_ms}, :none)

  @doc "Borra lo vencido en `now_ms`. Devuelve cuántas entradas quitó."
  def sweep(now_ms), do: sweep(__MODULE__, now_ms)

  def sweep(server, now_ms), do: call(server, {:sweep, now_ms}, 0)

  @doc "Cuántas entradas hay (vencidas o no, hasta que se limpien)."
  def size, do: size(__MODULE__)

  def size(server), do: call(server, :size, 0)

  # Si el proceso no responde, se actúa como si no hubiera memoria: el
  # comportamiento estricto de siempre, que nunca es inseguro
  defp call(server, message, fallback) do
    GenServer.call(server, message)
  catch
    :exit, _ -> fallback
  end

  # --- servidor ---

  # El estado es %{clave => {valor, vence_en_ms}}
  @impl true
  def init(:ok) do
    schedule_sweep()
    {:ok, %{}}
  end

  @impl true
  def handle_call({:remember, key, value, now_ms}, _from, entries) do
    # La limpieza de rutina es del barrido por temporizador. Aquí solo se limpia
    # si el tope se llenó, como último recurso para hacer lugar.
    entries =
      if map_size(entries) >= max_entries(), do: drop_expired(entries, now_ms), else: entries

    if map_size(entries) >= max_entries() and not Map.has_key?(entries, key) do
      {:reply, :full, entries}
    else
      {:reply, :ok, Map.put(entries, key, {value, now_ms + ttl_ms()})}
    end
  end

  def handle_call({:lookup, key, now_ms}, _from, entries) do
    case Map.get(entries, key) do
      {value, expires_at} when expires_at > now_ms -> {:reply, {:ok, value}, entries}
      _ -> {:reply, :none, entries}
    end
  end

  def handle_call({:sweep, now_ms}, _from, entries) do
    kept = drop_expired(entries, now_ms)
    {:reply, map_size(entries) - map_size(kept), kept}
  end

  def handle_call(:size, _from, entries), do: {:reply, map_size(entries), entries}

  @impl true
  def handle_info(:sweep, entries) do
    schedule_sweep()
    {:noreply, drop_expired(entries, System.system_time(:millisecond))}
  end

  defp drop_expired(entries, now_ms) do
    entries
    |> Enum.reject(fn {_key, {_value, expires_at}} -> expires_at <= now_ms end)
    |> Map.new()
  end

  defp schedule_sweep do
    case config(:sweep_every) do
      ms when is_integer(ms) and ms > 0 -> Process.send_after(self(), :sweep, ms)
      _ -> :ok
    end
  end

  defp ttl_ms, do: config(:ttl_seconds) * 1000
  defp max_entries, do: config(:max_entries)

  defp config(key), do: :civic |> Application.fetch_env!(__MODULE__) |> Keyword.fetch!(key)
end
