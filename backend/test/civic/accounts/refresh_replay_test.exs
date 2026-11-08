defmodule Civic.Accounts.RefreshReplayTest do
  # Cambia la configuración global: no puede correr en paralelo
  use ExUnit.Case, async: false

  alias Civic.Accounts.RefreshReplay

  @t0 1_000_000

  setup do
    original = Application.get_env(:civic, Civic.Accounts.RefreshReplay)

    Application.put_env(:civic, Civic.Accounts.RefreshReplay,
      ttl_seconds: 30,
      max_entries: 3,
      sweep_every: :never
    )

    on_exit(fn -> Application.put_env(:civic, Civic.Accounts.RefreshReplay, original) end)

    # Una instancia propia, para no depender de la que usa la aplicación
    {:ok, replay: start_supervised!({RefreshReplay, name: :refresh_replay_de_prueba})}
  end

  test "recuerda un valor y lo devuelve dentro de la ventana", %{replay: replay} do
    assert :ok = RefreshReplay.remember(replay, "clave", "valor", @t0)

    assert {:ok, "valor"} = RefreshReplay.lookup(replay, "clave", @t0 + 29_000)
  end

  test "pasada la ventana ya no lo devuelve", %{replay: replay} do
    :ok = RefreshReplay.remember(replay, "clave", "valor", @t0)

    assert :none = RefreshReplay.lookup(replay, "clave", @t0 + 30_000)
    assert :none = RefreshReplay.lookup(replay, "clave", @t0 + 31_000)
  end

  test "una clave que no se recordó no existe", %{replay: replay} do
    assert :none = RefreshReplay.lookup(replay, "otra", @t0)
  end

  test "consultar no alarga la ventana", %{replay: replay} do
    :ok = RefreshReplay.remember(replay, "clave", "valor", @t0)

    assert {:ok, _} = RefreshReplay.lookup(replay, "clave", @t0 + 20_000)
    assert :none = RefreshReplay.lookup(replay, "clave", @t0 + 31_000)
  end

  test "con el tope lleno no recuerda más (queda el comportamiento estricto)", %{replay: replay} do
    assert :ok = RefreshReplay.remember(replay, "a", "1", @t0)
    assert :ok = RefreshReplay.remember(replay, "b", "2", @t0)
    assert :ok = RefreshReplay.remember(replay, "c", "3", @t0)

    assert :full = RefreshReplay.remember(replay, "d", "4", @t0)
    assert :none = RefreshReplay.lookup(replay, "d", @t0)
    assert {:ok, "1"} = RefreshReplay.lookup(replay, "a", @t0)
  end

  test "al recordar, libera primero lo que ya venció", %{replay: replay} do
    :ok = RefreshReplay.remember(replay, "a", "1", @t0)
    :ok = RefreshReplay.remember(replay, "b", "2", @t0)
    :ok = RefreshReplay.remember(replay, "c", "3", @t0)

    # Pasados 31 s las tres vencieron: hay lugar otra vez
    assert :ok = RefreshReplay.remember(replay, "d", "4", @t0 + 31_000)
    assert RefreshReplay.size(replay) == 1
  end

  test "recordar no borra lo vencido mientras haya lugar (eso es del barrido)", %{replay: replay} do
    :ok = RefreshReplay.remember(replay, "a", "1", @t0)

    # Un `now` posterior no debe llevarse las entradas de otros: con relojes
    # distintos (como en los tests) se pisarían entre sí
    :ok = RefreshReplay.remember(replay, "b", "2", @t0 + 31_000)

    assert RefreshReplay.size(replay) == 2
  end

  test "sweep borra lo vencido y deja lo vigente", %{replay: replay} do
    :ok = RefreshReplay.remember(replay, "viejo", "1", @t0)
    :ok = RefreshReplay.remember(replay, "nuevo", "2", @t0 + 20_000)

    assert 1 = RefreshReplay.sweep(replay, @t0 + 31_000)

    assert RefreshReplay.size(replay) == 1
    assert {:ok, "2"} = RefreshReplay.lookup(replay, "nuevo", @t0 + 31_000)
  end
end
