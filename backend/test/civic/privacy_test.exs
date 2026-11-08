defmodule Civic.PrivacyTest do
  # No es async: algunos tests cambian la configuración de claves (global)
  use ExUnit.Case, async: false

  alias Civic.Privacy

  @account "0b1b6b0e-4f6e-4a0e-9d44-9a5d0e0f7a11"
  @other_account "7c9e6679-7425-40de-944b-e07fc1f90ae7"
  @incident "a3bb189e-8bf9-3888-9912-ace4e6543002"
  @other_incident "b3bb189e-8bf9-3888-9912-ace4e6543003"

  # Cambia la configuración de claves solo durante un test
  defp with_keys(update) when is_function(update, 1) do
    original = Application.fetch_env!(:civic, Privacy)
    Application.put_env(:civic, Privacy, update.(original))
    on_exit(fn -> Application.put_env(:civic, Privacy, original) end)
  end

  describe "dni_hash/2" do
    test "devuelve HMAC-SHA256 de 32 bytes con la versión de clave usada" do
      assert {:ok, %{hash: hash, version: 1}} = Privacy.dni_hash("12345678")
      assert byte_size(hash) == 32
    end

    test "es exactamente HMAC-SHA256(clave, etiqueta + DNI), calculado aparte" do
      key = Application.fetch_env!(:civic, Privacy)[:keys][{:verif, 1}]
      expected = :crypto.mac(:hmac, :sha256, key, "civic/dni/v1\0" <> "12345678")

      assert {:ok, %{hash: ^expected}} = Privacy.dni_hash("12345678")
    end

    test "es determinista (permite detectar un DNI repetido) y distingue DNIs" do
      {:ok, a} = Privacy.dni_hash("12345678")
      {:ok, b} = Privacy.dni_hash("12345678")
      {:ok, c} = Privacy.dni_hash("12345679")

      assert a == b
      assert a.hash != c.hash
    end

    test "el hash no contiene el número del DNI" do
      {:ok, %{hash: hash}} = Privacy.dni_hash("12345678")
      refute String.contains?(hash, "12345678")
      refute String.contains?(Base.encode16(hash), "12345678")
    end

    test "quita espacios alrededor, pero nada más" do
      assert Privacy.dni_hash(" 12345678\n") == Privacy.dni_hash("12345678")
      assert {:error, :invalid_dni} = Privacy.dni_hash("1234 5678")
    end

    test "solo acepta exactamente 8 dígitos" do
      for invalid <- ["", "1234567", "123456789", "1234567a", "12345678-9", "１２３４５６７８"] do
        assert {:error, :invalid_dni} = Privacy.dni_hash(invalid), "aceptó #{inspect(invalid)}"
      end
    end

    test "rechaza lo que no es texto (un entero perdería ceros a la izquierda)" do
      for invalid <- [nil, 12_345_678, 1.5, %{}, ["12345678"]] do
        assert {:error, :invalid_dni} = Privacy.dni_hash(invalid)
      end
    end

    test "con otra versión de clave el hash cambia y se informa la versión" do
      with_keys(fn config ->
        keys = Map.put(config[:keys], {:verif, 2}, :crypto.hash(:sha256, "otra clave"))
        Keyword.put(config, :keys, keys)
      end)

      {:ok, v1} = Privacy.dni_hash("12345678", version: 1)
      {:ok, v2} = Privacy.dni_hash("12345678", version: 2)

      assert v2.version == 2
      assert v1.hash != v2.hash
    end

    test "una versión sin clave configurada falla en vez de usar otra" do
      assert_raise ArgumentError, ~r/clave/, fn ->
        Privacy.dni_hash("12345678", version: 99)
      end
    end
  end

  describe "tokens por incidente" do
    test "son de 32 bytes y deterministas" do
      token = Privacy.voter_token(@account, @incident)

      assert byte_size(token) == 32
      assert token == Privacy.voter_token(@account, @incident)
      assert byte_size(Privacy.reporter_token(@account, @incident)) == 32
    end

    test "cambian con cada incidente: no se pueden enlazar los votos de una persona" do
      refute Privacy.voter_token(@account, @incident) ==
               Privacy.voter_token(@account, @other_incident)

      refute Privacy.reporter_token(@account, @incident) ==
               Privacy.reporter_token(@account, @other_incident)
    end

    test "cambian con la cuenta" do
      refute Privacy.voter_token(@account, @incident) ==
               Privacy.voter_token(@other_account, @incident)
    end

    test "el token de autor y el de votante de la misma cuenta son distintos" do
      # Si fueran iguales, quien lea la base uniría votos y reportes con un JOIN
      refute Privacy.reporter_token(@account, @incident) ==
               Privacy.voter_token(@account, @incident)
    end

    test "las claves de autor y de votante son independientes" do
      key = fn purpose ->
        Application.fetch_env!(:civic, Privacy)[:keys][{purpose, 1}]
      end

      refute key.(:rep) == key.(:vote)
      refute key.(:rep) == key.(:verif)
      refute key.(:vote) == key.(:verif)
    end

    test "no filtran los identificadores que los generan" do
      token = Privacy.voter_token(@account, @incident)
      refute String.contains?(token, @account)
      refute String.contains?(token, @incident)
    end

    test "exigen UUID válidos (no aceptan basura ni la ausencia)" do
      for bad <- [nil, "", "no-es-uuid", 123] do
        assert_raise ArgumentError, fn -> Privacy.voter_token(bad, @incident) end
        assert_raise ArgumentError, fn -> Privacy.reporter_token(@account, bad) end
      end
    end

    test "dan igual con mayúsculas o minúsculas en el UUID" do
      assert Privacy.voter_token(String.upcase(@account), @incident) ==
               Privacy.voter_token(@account, @incident)
    end
  end

  describe "same_token?/2" do
    test "compara en tiempo constante y sin fallar con tamaños distintos" do
      token = Privacy.reporter_token(@account, @incident)

      assert Privacy.same_token?(token, Privacy.reporter_token(@account, @incident))
      refute Privacy.same_token?(token, Privacy.reporter_token(@other_account, @incident))
      refute Privacy.same_token?(token, "corto")
      refute Privacy.same_token?(token, nil)
      refute Privacy.same_token?(nil, nil)
    end
  end

  describe "validate_config!/0" do
    test "pasa con la configuración de prueba" do
      assert :ok = Privacy.validate_config!()
    end

    test "falla si una clave es corta (menos de 32 bytes)" do
      with_keys(fn config ->
        Keyword.put(config, :keys, Map.put(config[:keys], {:vote, 1}, "corta"))
      end)

      assert_raise ArgumentError, ~r/32 bytes/, &Privacy.validate_config!/0
    end

    test "falla si la versión actual no tiene clave" do
      with_keys(fn config ->
        Keyword.put(config, :current, Map.put(config[:current], :rep, 7))
      end)

      assert_raise ArgumentError, ~r/rep/, &Privacy.validate_config!/0
    end

    test "falla si dos propósitos comparten la misma clave" do
      with_keys(fn config ->
        keys = config[:keys]
        Keyword.put(config, :keys, Map.put(keys, {:vote, 1}, keys[{:rep, 1}]))
      end)

      assert_raise ArgumentError, ~r/independientes|repetida/, &Privacy.validate_config!/0
    end
  end
end
