defmodule Civic.Evidence.DiskStoreTest do
  use ExUnit.Case, async: true

  alias Civic.Evidence.Store.Disk

  # Cada prueba usa su propio id: todas comparten la carpeta de pruebas
  defp new_id, do: Ecto.UUID.generate()

  defp root, do: Application.fetch_env!(:civic, Civic.Evidence)[:root]

  describe "put/2 y get/1" do
    test "guarda una foto y la devuelve igual" do
      id = new_id()

      assert Disk.put(id, "bytes de la foto") == :ok
      assert Disk.get(id) == {:ok, "bytes de la foto"}
    end

    test "una foto no se puede reemplazar: la primera se conserva" do
      id = new_id()
      :ok = Disk.put(id, "primera")

      assert Disk.put(id, "segunda") == {:error, :exists}
      assert Disk.get(id) == {:ok, "primera"}
    end

    test "pedir una foto que no existe" do
      assert Disk.get(new_id()) == {:error, :not_found}
    end

    test "el id en mayúsculas es el mismo archivo" do
      id = new_id()
      :ok = Disk.put(id, "x")

      assert Disk.get(String.upcase(id)) == {:ok, "x"}
    end

    test "una foto vacía se guarda y se lee (la revisión de contenido es de otra capa)" do
      id = new_id()

      assert Disk.put(id, <<>>) == :ok
      assert Disk.get(id) == {:ok, <<>>}
    end
  end

  describe "ids que no son un UUID" do
    test "se rechazan y no tocan el disco" do
      malos = [
        "../../etc/passwd",
        "..",
        "/etc/passwd",
        "abc",
        "",
        "#{new_id()}/../../x",
        "#{new_id()}.jpg",
        "#{new_id()}\0",
        nil,
        123,
        %{}
      ]

      for malo <- malos do
        assert Disk.put(malo, "x") == {:error, :invalid_id}, inspect(malo)
        assert Disk.get(malo) == {:error, :invalid_id}, inspect(malo)
        assert Disk.delete(malo) == {:error, :invalid_id}, inspect(malo)
      end
    end

    test "un id con ../ no crea nada fuera de la carpeta" do
      fuera = Path.join(Path.dirname(root()), "escapado.jpg")
      File.rm(fuera)

      Disk.put("../escapado", "x")

      refute File.exists?(fuera)
    end
  end

  describe "en disco" do
    test "el archivo es privado: solo lo lee y escribe el programa" do
      id = new_id()
      :ok = Disk.put(id, "x")

      %File.Stat{mode: mode} = File.stat!(Path.join(root(), id <> ".jpg"))
      assert Bitwise.band(mode, 0o777) == 0o600
    end

    test "la carpeta es privada" do
      :ok = Disk.put(new_id(), "x")

      %File.Stat{mode: mode} = File.stat!(root())
      assert Bitwise.band(mode, 0o777) == 0o700
    end

    test "no deja archivos temporales" do
      id = new_id()
      :ok = Disk.put(id, "x")
      {:error, :exists} = Disk.put(id, "y")

      temporales = root() |> File.ls!() |> Enum.filter(&String.contains?(&1, ".tmp"))

      assert temporales == []
    end

    test "con diez subidas a la vez del mismo id, solo una gana y queda intacta" do
      id = new_id()

      resultados =
        1..10
        |> Task.async_stream(fn n -> {n, Disk.put(id, "contenido #{n}")} end, max_concurrency: 10)
        |> Enum.map(fn {:ok, r} -> r end)

      ganadores = for {n, :ok} <- resultados, do: n
      assert [ganador] = ganadores
      assert Enum.count(resultados, fn {_, r} -> r == {:error, :exists} end) == 9
      assert Disk.get(id) == {:ok, "contenido #{ganador}"}
    end
  end

  describe "delete/1" do
    test "borra la foto" do
      id = new_id()
      :ok = Disk.put(id, "x")

      assert Disk.delete(id) == :ok
      assert Disk.get(id) == {:error, :not_found}
    end

    test "borrar una que no existe no es un error" do
      assert Disk.delete(new_id()) == :ok
    end

    test "tras borrar se puede volver a guardar" do
      id = new_id()
      :ok = Disk.put(id, "vieja")
      :ok = Disk.delete(id)

      assert Disk.put(id, "nueva") == :ok
      assert Disk.get(id) == {:ok, "nueva"}
    end
  end
end
