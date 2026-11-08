defmodule CivicWeb.HashGatePlugTest do
  # Cambia la configuración global del tope: no puede correr en paralelo
  use CivicWeb.ConnCase, async: false

  alias Civic.Accounts.User
  alias Civic.HashGate
  alias Civic.Repo

  @password "una contraseña larga y segura"

  setup do
    original = Application.get_env(:civic, Civic.HashGate)
    Application.put_env(:civic, Civic.HashGate, max_concurrent: 1)

    on_exit(fn ->
      Application.put_env(:civic, Civic.HashGate, original)
      # Que el cupo ocupado se libere antes del siguiente test
      _ = :sys.get_state(HashGate)
    end)

    :ok
  end

  # Ocupa el único cupo con otro proceso, como haría un login lento en paralelo
  defp fill_gate do
    pid = spawn(fn -> receive(do: (:stop -> :ok)) end)
    :ok = HashGate.acquire(pid)

    on_exit(fn ->
      ref = Process.monitor(pid)
      send(pid, :stop)

      receive do
        {:DOWN, ^ref, :process, ^pid, _} -> :ok
      end
    end)
  end

  defp json_post(conn, path, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> post(path, body)
  end

  test "con el cupo lleno, el login responde 503 con retry-after", %{conn: conn} do
    fill_gate()

    conn = json_post(conn, ~p"/v1/auth/login", %{"alias" => "Halcon-1", "password" => @password})

    assert %{"error" => %{"code" => "server_busy"}} = json_response(conn, 503)
    assert [retry] = get_resp_header(conn, "retry-after")
    assert String.to_integer(retry) >= 1
  end

  test "con el cupo lleno, el registro responde 503 y la cuenta no se crea", %{conn: conn} do
    fill_gate()

    conn =
      json_post(conn, ~p"/v1/auth/register", %{
        "alias" => "Ocupado-1",
        "password" => @password,
        "acepta_consentimiento" => true
      })

    assert %{"error" => %{"code" => "server_busy"}} = json_response(conn, 503)
    refute Repo.get_by(User, alias: "Ocupado-1")
  end

  test "refresh, logout y /me no usan cupo: no calculan hashes", %{conn: conn} do
    fill_gate()

    assert conn
           |> json_post(~p"/v1/auth/refresh", %{"refresh_token" => "x"})
           |> Map.fetch!(:status) == 401

    assert build_conn() |> json_post(~p"/v1/auth/logout", %{}) |> Map.fetch!(:status) == 204

    assert build_conn() |> get(~p"/v1/me") |> Map.fetch!(:status) == 401
  end

  test "al terminar la petición el cupo queda libre", %{conn: conn} do
    body = %{"alias" => "No-Existe-1", "password" => @password}

    # Con un solo cupo, dos logins seguidos solo pueden pasar si el primero lo liberó
    assert conn |> json_post(~p"/v1/auth/login", body) |> Map.fetch!(:status) == 401
    assert HashGate.in_use() == 0
    assert build_conn() |> json_post(~p"/v1/auth/login", body) |> Map.fetch!(:status) == 401
    assert HashGate.in_use() == 0
  end
end
