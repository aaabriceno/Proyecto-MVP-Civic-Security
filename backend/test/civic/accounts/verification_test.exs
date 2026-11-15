defmodule Civic.Accounts.VerificationTest do
  use Civic.DataCase, async: true

  alias Civic.Accounts
  alias Civic.Accounts.{User, Verification}
  alias Civic.Privacy
  alias Civic.Repo

  @password "una contraseña larga y segura"

  defp register! do
    {:ok, user} =
      Accounts.register(%{
        "alias" => "Ver-#{System.unique_integer([:positive])}",
        "password" => @password,
        "acepta_consentimiento" => true
      })

    user
  end

  # Un DNI distinto en cada llamada: dos pruebas en paralelo con el mismo número
  # se bloquearían entre sí en el índice único hasta que una termine
  defp dni do
    [:positive]
    |> System.unique_integer()
    |> rem(100_000_000)
    |> Integer.to_string()
    |> String.pad_leading(8, "0")
  end

  describe "verify_dni/2" do
    test "marca la cuenta como verificada y guarda solo el HMAC del DNI" do
      user = register!()
      dni = dni()
      {:ok, %{hash: hash, version: version}} = Privacy.dni_hash(dni)

      assert {:ok, %User{} = verified} = Verification.verify_dni(user, dni)

      assert verified.nivel == :verificado
      stored = Repo.get!(User, user.id)
      assert stored.nivel == :verificado
      assert stored.verif_hash == hash
      assert stored.verif_version == version
    end

    test "el número del DNI no queda en ninguna columna de la cuenta" do
      user = register!()
      dni = dni()

      {:ok, _} = Verification.verify_dni(user, dni)

      %{rows: [[fila]]} =
        Repo.query!("SELECT usuarios::text FROM usuarios WHERE id = $1", [
          Ecto.UUID.dump!(user.id)
        ])

      refute fila =~ dni
    end

    test "ignora los espacios de los extremos" do
      user = register!()
      dni = dni()
      {:ok, %{hash: hash}} = Privacy.dni_hash(dni)

      assert {:ok, _} = Verification.verify_dni(user, "  #{dni} ")

      assert Repo.get!(User, user.id).verif_hash == hash
    end

    test "el mismo DNI en otra cuenta se rechaza y esa cuenta no cambia" do
      primera = register!()
      segunda = register!()
      dni = dni()

      assert {:ok, _} = Verification.verify_dni(primera, dni)
      assert Verification.verify_dni(segunda, dni) == {:error, :dni_taken}

      intacta = Repo.get!(User, segunda.id)
      assert intacta.nivel == :invitado
      assert intacta.verif_hash == nil
      assert intacta.verif_version == nil
    end

    test "una cuenta ya verificada no puede cambiar de DNI" do
      user = register!()
      dni = dni()
      {:ok, verified} = Verification.verify_dni(user, dni)
      {:ok, %{hash: hash}} = Privacy.dni_hash(dni)

      assert Verification.verify_dni(verified, dni()) == {:error, :already_verified}
      assert Repo.get!(User, user.id).verif_hash == hash

      # Ni siquiera se mira el DNI que manda: ya está verificada
      assert Verification.verify_dni(verified, "mal") == {:error, :already_verified}
    end

    test "tampoco con una copia vieja de la cuenta (otra petición ya la verificó)" do
      user = register!()
      {:ok, _} = Verification.verify_dni(user, dni())
      otro = dni()
      {:ok, %{hash: hash_del_otro}} = Privacy.dni_hash(otro)

      # `user` es la copia de antes de verificar: sigue diciendo :invitado
      assert user.nivel == :invitado
      assert Verification.verify_dni(user, otro) == {:error, :already_verified}
      refute Repo.get!(User, user.id).verif_hash == hash_del_otro
    end

    test "un DNI con formato inválido se rechaza sin tocar la cuenta" do
      user = register!()

      for malo <- ["1234567", "123456789", "abcdefgh", "1234 678", "", nil, 12_345_678, %{}] do
        assert Verification.verify_dni(user, malo) == {:error, :invalid_dni}, inspect(malo)
      end

      assert Repo.get!(User, user.id).nivel == :invitado
    end

    test "una cuenta que ya no existe da :unauthorized" do
      user = register!()
      Repo.delete!(user)

      assert Verification.verify_dni(user, dni()) == {:error, :unauthorized}
    end

    test "al borrar la cuenta el DNI queda libre para otra" do
      vieja = register!()
      nueva = register!()
      dni = dni()
      {:ok, vieja} = Verification.verify_dni(vieja, dni)

      assert {:ok, _} = Accounts.delete_account(vieja, @password)

      assert {:ok, _} = Verification.verify_dni(nueva, dni)
    end
  end

  describe "intentos por día" do
    test "a partir del 6.º intento con DNI ya usados se bloquea y dice cuánto esperar" do
      ocupados = for _ <- 1..5, do: dni()

      for numero <- ocupados do
        assert {:ok, _} = Verification.verify_dni(register!(), numero)
      end

      user = register!()

      for numero <- ocupados do
        assert Verification.verify_dni(user, numero) == {:error, :dni_taken}
      end

      assert {:error, {:attempts_exceeded, retry_ms}} = Verification.verify_dni(user, dni())
      assert retry_ms > 0 and retry_ms <= :timer.hours(24)
    end

    test "el bloqueo también frena un DNI libre: no hay forma de seguir probando" do
      ocupado = dni()
      {:ok, _} = Verification.verify_dni(register!(), ocupado)
      user = register!()

      for _ <- 1..5, do: assert(Verification.verify_dni(user, ocupado) == {:error, :dni_taken})

      assert {:error, {:attempts_exceeded, _}} = Verification.verify_dni(user, dni())
      assert Repo.get!(User, user.id).nivel == :invitado
    end

    test "los DNI con formato inválido no gastan intentos" do
      user = register!()

      for _ <- 1..10, do: assert(Verification.verify_dni(user, "mal") == {:error, :invalid_dni})

      assert {:ok, _} = Verification.verify_dni(user, dni())
    end

    test "los intentos de una cuenta no afectan a otra" do
      ocupado = dni()
      {:ok, _} = Verification.verify_dni(register!(), ocupado)
      agotada = register!()
      for _ <- 1..5, do: Verification.verify_dni(agotada, ocupado)

      assert {:error, {:attempts_exceeded, _}} = Verification.verify_dni(agotada, dni())
      assert {:ok, _} = Verification.verify_dni(register!(), dni())
    end
  end
end
