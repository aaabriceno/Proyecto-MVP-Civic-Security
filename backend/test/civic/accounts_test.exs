defmodule Civic.AccountsTest do
  use Civic.DataCase, async: true

  alias Civic.Accounts
  alias Civic.Accounts.{Consent, User}

  @password "una contraseña larga y segura"
  @t0 ~U[2026-11-08 10:00:00.000000Z]

  defp attrs(overrides \\ %{}) do
    Map.merge(
      %{
        "alias" => "Halcon-482",
        "password" => @password,
        "acepta_consentimiento" => true
      },
      overrides
    )
  end

  defp register!(overrides \\ %{}) do
    {:ok, user} = Accounts.register(attrs(overrides))
    user
  end

  defp fail_login(times, opts) do
    for _ <- 1..times do
      assert {:error, :invalid_credentials} =
               Accounts.authenticate("Halcon-482", "contraseña equivocada!!", opts)
    end
  end

  describe "get_user/1" do
    test "devuelve la cuenta por su id" do
      user = register!()

      assert %User{id: id} = Accounts.get_user(user.id)
      assert id == user.id
    end

    test "devuelve nil si no existe o si el id no tiene forma de UUID" do
      assert Accounts.get_user(Ecto.UUID.generate()) == nil
      assert Accounts.get_user("no-es-uuid") == nil
      assert Accounts.get_user(nil) == nil
    end
  end

  describe "register/1" do
    test "crea una cuenta de nivel invitado con la contraseña en Argon2id" do
      assert {:ok, %User{} = user} = Accounts.register(attrs())

      assert user.alias == "Halcon-482"
      assert user.nivel == :invitado
      assert String.starts_with?(user.password_hash, "$argon2id$")
    end

    test "nunca conserva ni muestra la contraseña" do
      user = register!()

      assert user.password == nil
      refute inspect(user) =~ @password
      refute inspect(user) =~ "$argon2"

      stored =
        Repo.one(from u in "usuarios", where: u.alias == "Halcon-482", select: u.password_hash)

      refute String.contains?(stored, @password)
    end

    test "dos cuentas con la misma contraseña tienen hashes distintos (sal aleatoria)" do
      a = register!(%{"alias" => "Halcon-482"})
      b = register!(%{"alias" => "Zorro-190"})

      refute a.password_hash == b.password_hash
    end

    test "registra la versión del consentimiento aceptado" do
      user = register!()

      consent = Repo.one!(from c in Consent, where: c.usuario_id == ^user.id)
      assert consent.version == Accounts.consent_version()
      assert %DateTime{} = consent.aceptado_en
    end

    test "sin aceptar el consentimiento no se crea nada" do
      for value <- [false, nil, "false"] do
        assert {:error, changeset} = Accounts.register(attrs(%{"acepta_consentimiento" => value}))
        assert errors_on(changeset).acepta_consentimiento != []
      end

      assert {:error, changeset} =
               Accounts.register(Map.delete(attrs(), "acepta_consentimiento"))

      assert errors_on(changeset).acepta_consentimiento != []
      assert Repo.aggregate(User, :count) == 0
      assert Repo.aggregate(Consent, :count) == 0
    end

    test "ignora campos que el cliente no debe poder fijar (asignación masiva)" do
      user =
        register!(%{
          "nivel" => "verificado",
          "intentos_fallidos" => 99,
          "bloqueado_hasta" => "2099-01-01T00:00:00Z",
          "id" => Ecto.UUID.generate()
        })

      assert user.nivel == :invitado
      assert user.intentos_fallidos == 0
      assert user.bloqueado_hasta == nil
    end

    test "si los datos no son válidos no gasta tiempo en calcular el hash" do
      changeset = User.registration_changeset(%User{}, attrs(%{"alias" => "x"}))

      refute changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :password_hash) == nil
    end
  end

  describe "register/1 - alias" do
    test "es obligatorio" do
      assert {:error, cs} = Accounts.register(Map.delete(attrs(), "alias"))
      assert errors_on(cs).alias != []
    end

    test "debe tener entre 3 y 20 caracteres" do
      for alias_ <- ["ab", String.duplicate("a", 21)] do
        assert {:error, cs} = Accounts.register(attrs(%{"alias" => alias_}))
        assert Enum.any?(errors_on(cs).alias, &(&1 =~ "entre 3 y 20"))
      end

      assert {:ok, _} = Accounts.register(attrs(%{"alias" => String.duplicate("a", 20)}))
    end

    test "solo admite letras sin tilde, números, guion, guion bajo y punto" do
      invalid = [
        "hola mundo",
        "ñandú",
        "a@b.c",
        "<script>",
        "alias\u202Eevil",
        "tab\tulado",
        "nul\0byte",
        "emoji😀😀"
      ]

      for alias_ <- invalid do
        assert {:error, cs} = Accounts.register(attrs(%{"alias" => alias_}))
        assert errors_on(cs).alias != [], "aceptó #{inspect(alias_)}"
      end

      for alias_ <- ["a.b-c_d", "USER_01", "x-y.z"] do
        assert {:ok, _} = Accounts.register(attrs(%{"alias" => alias_}))
      end
    end

    test "se recortan los espacios de los extremos" do
      assert {:ok, user} = Accounts.register(attrs(%{"alias" => "  Halcon-482 \n"}))
      assert user.alias == "Halcon-482"
    end

    test "es único sin distinguir mayúsculas de minúsculas" do
      register!(%{"alias" => "Halcon-482"})

      for dup <- ["Halcon-482", "halcon-482", "HALCON-482"] do
        assert {:error, cs} = Accounts.register(attrs(%{"alias" => dup}))
        assert Enum.any?(errors_on(cs).alias, &(&1 =~ "ya está en uso"))
      end
    end
  end

  describe "register/1 - contraseña" do
    test "es obligatoria" do
      assert {:error, cs} = Accounts.register(Map.delete(attrs(), "password"))
      assert errors_on(cs).password != []
    end

    test "exige al menos 12 caracteres, sin reglas de composición" do
      assert {:error, cs} = Accounts.register(attrs(%{"password" => "corta-123"}))
      assert Enum.any?(errors_on(cs).password, &(&1 =~ "al menos 12"))

      # una frase larga solo en minúsculas es válida (NIST 800-63B)
      assert {:ok, _} = Accounts.register(attrs(%{"password" => "mi gato come pescado hoy"}))
    end

    test "tiene un máximo para que no sirva de excusa para gastar CPU" do
      assert {:error, cs} = Accounts.register(attrs(%{"password" => String.duplicate("ab", 70)}))
      assert Enum.any?(errors_on(cs).password, &(&1 =~ "como máximo 128"))
    end

    test "no admite caracteres de control" do
      for password <- ["contraseña\0larga!!", "contraseña\tlarga!!", "contraseña\nlarga!!"] do
        assert {:error, cs} = Accounts.register(attrs(%{"password" => password}))
        assert Enum.any?(errors_on(cs).password, &(&1 =~ "control")), inspect(password)
      end
    end

    test "no puede contener el alias" do
      assert {:error, cs} = Accounts.register(attrs(%{"password" => "mi-HALCON-482-secreto"}))
      assert Enum.any?(errors_on(cs).password, &(&1 =~ "alias"))
    end

    test "rechaza contraseñas con muy pocos caracteres distintos" do
      assert {:error, cs} = Accounts.register(attrs(%{"password" => "aaaaaaaaaaaaaaaa"}))
      assert Enum.any?(errors_on(cs).password, &(&1 =~ "simple"))
    end

    test "no es un texto válido si no es UTF-8" do
      assert {:error, cs} =
               Accounts.register(attrs(%{"password" => <<0xFF, 0xFE>> <> "abcdefghijkl"}))

      assert errors_on(cs).password != []
    end
  end

  describe "authenticate/3" do
    test "con credenciales correctas devuelve la cuenta" do
      user = register!()

      assert {:ok, %User{id: id}} = Accounts.authenticate("Halcon-482", @password)
      assert id == user.id
    end

    test "el alias no distingue mayúsculas ni espacios de los extremos" do
      user = register!()

      assert {:ok, %User{id: id}} = Accounts.authenticate("  halcon-482 ", @password)
      assert id == user.id
    end

    test "una contraseña equivocada da un error genérico" do
      register!()

      assert {:error, :invalid_credentials} =
               Accounts.authenticate("Halcon-482", "otra contraseña larga")
    end

    test "un alias inexistente da EXACTAMENTE el mismo error (no revela cuentas)" do
      register!()

      wrong_password = Accounts.authenticate("Halcon-482", "otra contraseña larga")
      unknown_alias = Accounts.authenticate("No-Existe-1", "otra contraseña larga")

      assert wrong_password == unknown_alias
    end

    test "entradas que no son texto no rompen y fallan igual" do
      for {a, p} <- [{nil, nil}, {nil, @password}, {"Halcon-482", nil}, {123, "x"}, {%{}, []}] do
        assert {:error, :invalid_credentials} = Accounts.authenticate(a, p)
      end
    end

    test "una cuenta sin contraseña (invitado) no puede iniciar sesión" do
      Repo.insert!(%User{alias: "Invitado-77", nivel: :invitado})

      assert {:error, :invalid_credentials} = Accounts.authenticate("Invitado-77", @password)
      assert {:error, :invalid_credentials} = Accounts.authenticate("Invitado-77", "")
    end

    test "la contraseña se normaliza (NFKC): da igual cómo la escriba el teclado" do
      # "ñ" como un solo carácter (U+00F1) y como "n" + tilde combinada (U+0303)
      composed = "contrase\u00F1a-larga-1"
      decomposed = "contrasen\u0303a-larga-1"
      assert composed != decomposed
      register!(%{"password" => composed})

      assert {:ok, _} = Accounts.authenticate("Halcon-482", composed)
      assert {:ok, _} = Accounts.authenticate("Halcon-482", decomposed)
    end
  end

  describe "authenticate/3 - bloqueo por intentos fallidos" do
    test "cuenta los fallos y se bloquea desde el quinto" do
      register!()

      fail_login(4, now: @t0)
      assert Repo.get_by!(User, alias: "Halcon-482").intentos_fallidos == 4
      assert Repo.get_by!(User, alias: "Halcon-482").bloqueado_hasta == nil

      # el 5.º fallo todavía responde como cualquier otro...
      fail_login(1, now: @t0)

      # ...pero la cuenta queda bloqueada 60 s, aunque ahora acierten
      assert {:error, {:locked, 30}} =
               Accounts.authenticate("Halcon-482", @password, now: DateTime.add(@t0, 30))
    end

    test "durante el bloqueo no se acepta ni la contraseña correcta" do
      register!()
      fail_login(5, now: @t0)

      assert {:error, {:locked, seconds}} =
               Accounts.authenticate("Halcon-482", @password, now: @t0)

      assert seconds in 1..60
    end

    test "pasado el bloqueo se puede entrar y el contador vuelve a cero" do
      register!()
      fail_login(5, now: @t0)

      later = DateTime.add(@t0, 61)
      assert {:ok, %User{}} = Accounts.authenticate("Halcon-482", @password, now: later)

      user = Repo.get_by!(User, alias: "Halcon-482")
      assert user.intentos_fallidos == 0
      assert user.bloqueado_hasta == nil
    end

    test "cada fallo posterior duplica la espera, con tope de 15 minutos" do
      register!()
      fail_login(5, now: @t0)

      # 6.º fallo (tras el primer bloqueo): 2 minutos
      t1 = DateTime.add(@t0, 61)
      fail_login(1, now: t1)
      assert {:error, {:locked, 120}} = Accounts.authenticate("Halcon-482", @password, now: t1)

      # fallos seguidos: 4, 8, 15 (tope) minutos...
      {t, _} =
        Enum.reduce(1..8, {t1, 0}, fn _, {t, _} ->
          next = DateTime.add(t, 16 * 60)
          fail_login(1, now: next)
          {next, 0}
        end)

      assert {:error, {:locked, 900}} = Accounts.authenticate("Halcon-482", @password, now: t)
    end

    test "los fallos viejos (más de 1 hora) no se acumulan" do
      register!()
      fail_login(4, now: @t0)

      fail_login(1, now: DateTime.add(@t0, 2 * 3600))

      user = Repo.get_by!(User, alias: "Halcon-482")
      assert user.intentos_fallidos == 1
      assert user.bloqueado_hasta == nil
    end

    test "un acierto antes del bloqueo borra los fallos" do
      register!()
      fail_login(3, now: @t0)

      assert {:ok, _} = Accounts.authenticate("Halcon-482", @password, now: @t0)
      assert Repo.get_by!(User, alias: "Halcon-482").intentos_fallidos == 0
    end

    test "el bloqueo de una cuenta no afecta a otra" do
      register!()
      register!(%{"alias" => "Zorro-190"})
      fail_login(5, now: @t0)

      assert {:ok, _} = Accounts.authenticate("Zorro-190", @password, now: @t0)
    end
  end
end
