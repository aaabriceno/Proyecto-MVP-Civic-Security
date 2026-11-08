defmodule Civic.HashGateTest do
  # Cambia la configuración global del tope: no puede correr en paralelo
  use ExUnit.Case, async: false

  alias Civic.HashGate

  setup do
    original = Application.get_env(:civic, Civic.HashGate)
    Application.put_env(:civic, Civic.HashGate, max_concurrent: 2)
    on_exit(fn -> Application.put_env(:civic, Civic.HashGate, original) end)

    # Una instancia propia, para no depender de la que usa la aplicación
    gate = start_supervised!({HashGate, name: :hash_gate_de_prueba})
    {:ok, gate: gate}
  end

  # Un proceso que ocupa su cupo hasta que se le dice que termine
  defp holder do
    pid = spawn(fn -> receive(do: (:stop -> :ok)) end)
    on_exit(fn -> send(pid, :stop) end)
    pid
  end

  test "da cupo hasta el máximo y después responde :busy", %{gate: gate} do
    assert :ok = HashGate.acquire(gate, holder())
    assert :ok = HashGate.acquire(gate, holder())
    assert :busy = HashGate.acquire(gate, holder())
    assert HashGate.in_use(gate) == 2
  end

  test "liberar un cupo deja entrar a otro", %{gate: gate} do
    uno = holder()
    :ok = HashGate.acquire(gate, uno)
    :ok = HashGate.acquire(gate, holder())
    :busy = HashGate.acquire(gate, holder())

    HashGate.release(gate, uno)

    assert :ok = HashGate.acquire(gate, holder())
  end

  test "pedir cupo dos veces con el mismo proceso no ocupa dos", %{gate: gate} do
    uno = holder()

    assert :ok = HashGate.acquire(gate, uno)
    assert :ok = HashGate.acquire(gate, uno)
    assert HashGate.in_use(gate) == 1
  end

  test "si el proceso que tenía el cupo muere sin liberarlo, el cupo se recupera", %{gate: gate} do
    uno = holder()
    otro = holder()
    :ok = HashGate.acquire(gate, uno)
    :ok = HashGate.acquire(gate, otro)
    :busy = HashGate.acquire(gate, holder())

    ref = Process.monitor(uno)
    Process.exit(uno, :kill)
    assert_receive {:DOWN, ^ref, :process, ^uno, :killed}
    # Espera a que el semáforo haya procesado el aviso de muerte
    _ = :sys.get_state(gate)

    assert :ok = HashGate.acquire(gate, holder())
  end

  test "liberar un cupo que no se tiene no hace nada", %{gate: gate} do
    :ok = HashGate.acquire(gate, holder())

    HashGate.release(gate, holder())
    _ = :sys.get_state(gate)

    assert HashGate.in_use(gate) == 1
  end
end
