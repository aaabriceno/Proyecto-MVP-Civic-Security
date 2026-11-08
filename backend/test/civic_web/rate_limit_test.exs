defmodule CivicWeb.RateLimitTest do
  # Modifica la configuración global: no puede correr en paralelo
  use CivicWeb.ConnCase, async: false

  alias Civic.Incidents.Incident
  alias Civic.Repo

  @valid %{"tipo" => "robo", "lat" => -16.3963, "lng" => -71.5340}

  setup do
    original = Application.fetch_env!(:civic, CivicWeb.RateLimit)
    header = Application.get_env(:civic, :client_ip_header)

    Application.put_env(:civic, CivicWeb.RateLimit,
      write: {3, 60_000},
      read: {5, 60_000},
      socket: {2, 60_000},
      # Ventana de una hora: el contador es de ventana fija y, si el minuto
      # cambiara a mitad de un test, se reiniciaría y el test fallaría sin motivo
      register: {2, :timer.hours(1)},
      login: {2, :timer.hours(1)},
      refresh: {2, :timer.hours(1)}
    )

    on_exit(fn ->
      Application.put_env(:civic, CivicWeb.RateLimit, original)
      Application.put_env(:civic, :client_ip_header, header)
    end)

    :ok
  end

  # Cada test usa su propia IP: el contador vive en memoria entre tests
  defp unique_ip do
    n = :erlang.unique_integer([:positive])
    {10, rem(n, 250) + 1, rem(div(n, 250), 250) + 1, rem(div(n, 62_500), 250) + 1}
  end

  # Un cliente "detrás del proxy" distinto en cada llamada (el contador vive en memoria)
  defp unique_client do
    n = :erlang.unique_integer([:positive])
    "198.#{rem(n, 250) + 1}.#{rem(div(n, 250), 250) + 1}.#{rem(div(n, 62_500), 250) + 1}"
  end

  defp post_incident(conn, ip, headers \\ []) do
    conn = %{conn | remote_ip: ip}

    conn =
      Enum.reduce(headers, conn, fn {k, v}, acc -> put_req_header(acc, k, v) end)

    conn
    |> put_req_header("content-type", "application/json")
    |> put_req_header("idempotency-key", Ecto.UUID.generate())
    |> post(~p"/v1/incidents", @valid)
  end

  test "POST /v1/incidents: pasado el límite responde 429 con Retry-After", %{conn: conn} do
    ip = unique_ip()

    for _ <- 1..3, do: assert(post_incident(conn, ip).status == 201)

    conn = post_incident(build_conn(), ip)
    assert %{"error" => %{"code" => "rate_limited"}} = json_response(conn, 429)
    assert [retry] = get_resp_header(conn, "retry-after")
    assert String.to_integer(retry) in 1..60
  end

  test "un reporte bloqueado por el límite no se guarda", %{conn: conn} do
    ip = unique_ip()
    for _ <- 1..3, do: post_incident(conn, ip)
    antes = Repo.aggregate(Incident, :count)

    assert post_incident(build_conn(), ip).status == 429
    assert Repo.aggregate(Incident, :count) == antes
  end

  test "cada IP tiene su propio contador", %{conn: conn} do
    una = unique_ip()
    otra = unique_ip()
    for _ <- 1..3, do: post_incident(conn, una)

    assert post_incident(build_conn(), una).status == 429
    assert post_incident(build_conn(), otra).status == 201
  end

  defp auth_post(ip, path, body) do
    %{build_conn() | remote_ip: ip}
    |> put_req_header("content-type", "application/json")
    |> post(path, body)
  end

  defp new_account(n),
    do: %{
      "alias" => "Limite-#{:erlang.unique_integer([:positive])}-#{n}",
      "password" => "una contraseña larga y segura",
      "acepta_consentimiento" => true
    }

  describe "endpoints de cuentas" do
    test "register: pasado el límite responde 429 y la cuenta no se crea" do
      ip = unique_ip()

      for n <- 1..2,
          do: assert(auth_post(ip, ~p"/v1/auth/register", new_account(n)).status == 201)

      bloqueada = new_account(3)
      conn = auth_post(ip, ~p"/v1/auth/register", bloqueada)

      assert %{"error" => %{"code" => "rate_limited"}} = json_response(conn, 429)
      assert [_] = get_resp_header(conn, "retry-after")
      refute Repo.get_by(Civic.Accounts.User, alias: bloqueada["alias"])
    end

    test "login: pasado el límite responde 429 (distinto del bloqueo de la cuenta)" do
      ip = unique_ip()
      body = %{"alias" => "No-Existe-1", "password" => "una contraseña larga y segura"}

      for _ <- 1..2, do: assert(auth_post(ip, ~p"/v1/auth/login", body).status == 401)

      conn = auth_post(ip, ~p"/v1/auth/login", body)
      assert %{"error" => %{"code" => "rate_limited"}} = json_response(conn, 429)
    end

    test "refresh y logout comparten límite" do
      ip = unique_ip()

      assert auth_post(ip, ~p"/v1/auth/refresh", %{"refresh_token" => "x"}).status == 401
      assert auth_post(ip, ~p"/v1/auth/logout", %{"refresh_token" => "x"}).status == 204

      assert auth_post(ip, ~p"/v1/auth/refresh", %{"refresh_token" => "x"}).status == 429
    end

    test "cada acción tiene su propio contador" do
      ip = unique_ip()
      for n <- 1..2, do: auth_post(ip, ~p"/v1/auth/register", new_account(n))
      assert auth_post(ip, ~p"/v1/auth/register", new_account(3)).status == 429

      # Agotar el registro no afecta al login desde la misma IP
      body = %{"alias" => "No-Existe-1", "password" => "una contraseña larga y segura"}
      assert auth_post(ip, ~p"/v1/auth/login", body).status == 401
    end
  end

  test "las lecturas también se limitan", %{conn: conn} do
    ip = unique_ip()
    url = ~p"/v1/map/snapshot?bbox=-71.75,-16.60,-71.40,-16.25"

    for _ <- 1..5, do: assert(get(%{conn | remote_ip: ip}, url).status == 200)
    assert get(%{build_conn() | remote_ip: ip}, url).status == 429
  end

  test "/health también se limita (evita usarlo para saturar la BD)", %{conn: conn} do
    ip = unique_ip()
    for _ <- 1..5, do: get(%{conn | remote_ip: ip}, ~p"/health")
    assert get(%{build_conn() | remote_ip: ip}, ~p"/health").status == 429
  end

  test "una cabecera de IP no se obedece si no está configurada (anti-suplantación)",
       %{conn: conn} do
    ip = unique_ip()

    for i <- 1..3, do: post_incident(conn, ip, [{"x-real-ip", "9.9.9.#{i}"}])

    # Cambiar la cabecera no da un contador nuevo: sigue contando la IP real
    assert post_incident(build_conn(), ip, [{"x-real-ip", "9.9.9.200"}]).status == 429
  end

  test "con un proxy de confianza configurado se usa su cabecera", %{conn: conn} do
    Application.put_env(:civic, :client_ip_header, "x-real-ip")
    proxy = unique_ip()
    uno = unique_client()
    otro = unique_client()

    for _ <- 1..3, do: post_incident(conn, proxy, [{"x-real-ip", uno}])

    # Todos llegan por la misma IP del proxy, pero son clientes distintos
    assert post_incident(build_conn(), proxy, [{"x-real-ip", uno}]).status == 429
    assert post_incident(build_conn(), proxy, [{"x-real-ip", otro}]).status == 201
  end
end
