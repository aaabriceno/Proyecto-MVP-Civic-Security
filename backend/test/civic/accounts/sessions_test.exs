defmodule Civic.Accounts.SessionsTest do
  use Civic.DataCase, async: true

  alias Civic.Accounts
  alias Civic.Accounts.Sessions

  @t0 ~U[2026-11-08 10:00:00.000000Z]

  defp user!(alias_ \\ "Halcon-482") do
    {:ok, user} =
      Accounts.register(%{
        "alias" => alias_,
        "password" => "una contraseña larga y segura",
        "acepta_consentimiento" => true
      })

    user
  end

  defp tras_dias(dias), do: DateTime.add(@t0, dias, :day)

  # Lee las filas tal como quedaron en la base, sin pasar por ningún esquema
  defp filas(user) do
    Repo.all(
      from t in "refresh_tokens",
        where: t.usuario_id == type(^user.id, :binary_id),
        select: %{
          token_hash: t.token_hash,
          familia: t.familia,
          creado_en: t.creado_en,
          expira_en: t.expira_en,
          revocado_en: t.revocado_en
        }
    )
  end

  describe "issue/2" do
    test "entrega un access token, un refresh token y cuánto dura el access" do
      user = user!()

      assert {:ok, %{access_token: access, refresh_token: refresh, expires_in: 900}} =
               Sessions.issue(user, now: @t0)

      assert is_binary(access)
      # 32 bytes aleatorios en base64 seguro para URL, sin relleno
      assert refresh =~ ~r/\A[A-Za-z0-9_-]{43}\z/
    end

    test "dos inicios de sesión nunca dan el mismo refresh token" do
      user = user!()

      {:ok, uno} = Sessions.issue(user, now: @t0)
      {:ok, dos} = Sessions.issue(user, now: @t0)

      refute uno.refresh_token == dos.refresh_token
    end

    test "en la base queda solo el SHA-256 del refresh token, nunca el token" do
      user = user!()

      {:ok, %{refresh_token: refresh}} = Sessions.issue(user, now: @t0)

      assert [fila] = filas(user)
      assert fila.token_hash == :crypto.hash(:sha256, refresh)
      refute fila.token_hash == refresh
      refute fila.token_hash == Base.url_decode64!(refresh, padding: false)
    end

    test "las fechas son días, sin hora, y el refresh vence a los 30 días" do
      user = user!()

      {:ok, _} = Sessions.issue(user, now: @t0)

      assert [%{creado_en: ~D[2026-11-08], expira_en: ~D[2026-12-08], revocado_en: nil}] =
               filas(user)
    end
  end

  describe "verify_access/1" do
    test "un access token recién emitido devuelve el id de la cuenta" do
      user = user!()
      {:ok, %{access_token: access}} = Sessions.issue(user)

      assert {:ok, id} = Sessions.verify_access(access)
      assert id == user.id
    end

    test "rechaza basura y valores que no son texto" do
      assert {:error, :invalid_token} = Sessions.verify_access("esto-no-es-un-token")
      assert {:error, :invalid_token} = Sessions.verify_access("")
      assert {:error, :invalid_token} = Sessions.verify_access(nil)
      assert {:error, :invalid_token} = Sessions.verify_access(123)
    end

    test "rechaza un token al que le cambiaron un carácter" do
      user = user!()
      {:ok, %{access_token: access}} = Sessions.issue(user)

      # Cambia un carácter del MEDIO de la firma. No el último: en base64 el
      # último carácter de una firma de 32 bytes solo usa 4 de sus 6 bits, así que
      # cambiarlo a veces escribe la misma firma de otra forma y el token sigue
      # siendo válido (fallaba 1 de cada 16 corridas).
      {inicio, resto} = String.split_at(access, -20)
      {caracter, final} = String.split_at(resto, 1)
      manipulado = inicio <> if(caracter == "A", do: "B", else: "A") <> final

      assert {:error, :invalid_token} = Sessions.verify_access(manipulado)
    end

    test "rechaza un access token con más de 15 minutos" do
      user = user!()
      hace_16_min = DateTime.add(DateTime.utc_now(), -16 * 60, :second)
      {:ok, %{access_token: access}} = Sessions.issue(user, now: hace_16_min)

      assert {:error, :invalid_token} = Sessions.verify_access(access)
    end

    test "rechaza un token firmado con otro propósito (otra sal)" do
      user = user!()
      secreto = Application.fetch_env!(:civic, CivicWeb.Endpoint)[:secret_key_base]
      ajeno = Phoenix.Token.sign(secreto, "otro proposito", user.id)

      assert {:error, :invalid_token} = Sessions.verify_access(ajeno)
    end
  end

  describe "refresh/2" do
    test "entrega un par nuevo y distinto, con un access token que sirve" do
      user = user!()
      {:ok, primero} = Sessions.issue(user)

      # Con el reloj real: el access token se valida contra la hora de verdad
      assert {:ok, segundo} = Sessions.refresh(primero.refresh_token)

      refute segundo.refresh_token == primero.refresh_token
      assert segundo.expires_in == 900
      assert {:ok, id} = Sessions.verify_access(segundo.access_token)
      assert id == user.id
    end

    test "el token viejo queda usado y el nuevo sigue en la misma familia" do
      user = user!()
      {:ok, primero} = Sessions.issue(user, now: @t0)
      {:ok, _} = Sessions.refresh(primero.refresh_token, now: @t0)

      assert {[viejo], [nuevo]} = Enum.split_with(filas(user), & &1.revocado_en)
      assert viejo.revocado_en == ~D[2026-11-08]
      assert viejo.familia == nuevo.familia
    end

    test "reusar un refresh ya usado falla" do
      user = user!()
      {:ok, primero} = Sessions.issue(user, now: @t0)
      {:ok, _} = Sessions.refresh(primero.refresh_token, now: @t0)

      assert {:error, :invalid_token} = Sessions.refresh(primero.refresh_token, now: @t0)
    end

    test "al detectar el reuso se revoca toda la familia, también el token nuevo" do
      user = user!()
      {:ok, primero} = Sessions.issue(user, now: @t0)
      {:ok, segundo} = Sessions.refresh(primero.refresh_token, now: @t0)

      # Alguien presenta el token viejo: había una copia en circulación
      {:error, :invalid_token} = Sessions.refresh(primero.refresh_token, now: @t0)

      assert {:error, :invalid_token} = Sessions.refresh(segundo.refresh_token, now: @t0)
      assert Enum.all?(filas(user), &(&1.revocado_en == ~D[2026-11-08]))
    end

    test "el reuso en una sesión no toca las otras sesiones de la misma cuenta" do
      user = user!()
      {:ok, tablet} = Sessions.issue(user, now: @t0)
      {:ok, celular} = Sessions.issue(user, now: @t0)
      {:ok, _} = Sessions.refresh(tablet.refresh_token, now: @t0)
      {:error, :invalid_token} = Sessions.refresh(tablet.refresh_token, now: @t0)

      assert {:ok, _} = Sessions.refresh(celular.refresh_token, now: @t0)
    end

    test "un token desconocido o con forma rara falla siempre igual" do
      assert {:error, :invalid_token} = Sessions.refresh(String.duplicate("a", 43), now: @t0)
      assert {:error, :invalid_token} = Sessions.refresh("", now: @t0)
      assert {:error, :invalid_token} = Sessions.refresh(nil, now: @t0)
      assert {:error, :invalid_token} = Sessions.refresh(123, now: @t0)
    end

    test "sirve hasta el final de su día de vencimiento" do
      user = user!()
      {:ok, %{refresh_token: refresh}} = Sessions.issue(user, now: @t0)

      assert {:ok, _} = Sessions.refresh(refresh, now: tras_dias(30))
    end

    test "al día siguiente de su vencimiento ya no sirve" do
      user = user!()
      {:ok, %{refresh_token: refresh}} = Sessions.issue(user, now: @t0)

      assert {:error, :invalid_token} = Sessions.refresh(refresh, now: tras_dias(31))
    end

    test "rotar no alarga la sesión: vence a los 30 días del inicio de sesión aunque se use" do
      user = user!()
      {:ok, t1} = Sessions.issue(user, now: @t0)
      {:ok, t2} = Sessions.refresh(t1.refresh_token, now: tras_dias(10))
      {:ok, t3} = Sessions.refresh(t2.refresh_token, now: tras_dias(20))
      # El día 30 todavía sirve (vale hasta el final de ese día)
      {:ok, t4} = Sessions.refresh(t3.refresh_token, now: tras_dias(30))

      assert {:error, :invalid_token} = Sessions.refresh(t4.refresh_token, now: tras_dias(31))
      # Todos los tokens de la familia heredan el vencimiento del inicio de sesión
      assert Enum.all?(filas(user), &(&1.expira_en == ~D[2026-12-08]))
    end
  end

  describe "revoke/1 (cerrar sesión)" do
    test "el refresh token deja de servir, también el de la rotación más reciente" do
      user = user!()
      {:ok, primero} = Sessions.issue(user, now: @t0)
      {:ok, segundo} = Sessions.refresh(primero.refresh_token, now: @t0)

      assert :ok = Sessions.revoke(segundo.refresh_token, now: @t0)

      assert {:error, :invalid_token} = Sessions.refresh(segundo.refresh_token, now: @t0)
    end

    test "con un token desconocido responde :ok sin revelar nada" do
      assert :ok = Sessions.revoke(String.duplicate("a", 43), now: @t0)
      assert :ok = Sessions.revoke(nil, now: @t0)
    end

    test "no cierra las otras sesiones de la misma cuenta" do
      user = user!()
      {:ok, tablet} = Sessions.issue(user, now: @t0)
      {:ok, celular} = Sessions.issue(user, now: @t0)

      :ok = Sessions.revoke(tablet.refresh_token, now: @t0)

      assert {:ok, _} = Sessions.refresh(celular.refresh_token, now: @t0)
    end
  end
end
