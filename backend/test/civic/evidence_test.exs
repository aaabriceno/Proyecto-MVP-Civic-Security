defmodule Civic.EvidenceTest do
  use Civic.DataCase, async: true

  import Civic.JpegFixtures

  alias Civic.Accounts
  alias Civic.Evidence
  alias Civic.Evidence.Store.Disk
  alias Civic.Incidents
  alias Civic.Incidents.Incident
  alias Civic.Repo

  # Un almacenamiento que siempre falla, para probar que no queda nada a medias
  defmodule FailingStore do
    @behaviour Civic.Evidence.Store
    def put(_id, _binary), do: {:error, :io}
    def get(_id), do: {:error, :io}
    def delete(_id), do: :ok
  end

  defp register! do
    {:ok, user} =
      Accounts.register(%{
        "alias" => "Foto-#{System.unique_integer([:positive])}",
        "password" => "una contraseña larga y segura",
        "acepta_consentimiento" => true
      })

    user
  end

  defp report!(user) do
    {:ok, :created, incident} =
      Incidents.report_incident(
        user,
        %{"tipo" => "robo", "lat" => -16.4, "lng" => -71.53},
        Ecto.UUID.generate()
      )

    incident
  end

  defp flag(incident), do: Repo.get!(Incident, incident.id).tiene_foto

  setup do
    author = register!()
    {:ok, author: author, incident: report!(author)}
  end

  describe "attach_photo/3" do
    test "el autor sube su foto y el incidente queda marcado", %{author: a, incident: i} do
      assert {:ok, %Incident{tiene_foto: true}} = Evidence.attach_photo(a, i.id, clean())

      assert flag(i)
      assert Disk.get(i.id) == {:ok, clean()}
    end

    test "un reporte nuevo nunca nace con foto", %{incident: i} do
      refute i.tiene_foto
    end

    test "no cambia nada más del incidente", %{author: a, incident: i} do
      {:ok, subido} = Evidence.attach_photo(a, i.id, clean())

      assert {subido.tipo, subido.estado, subido.descripcion, subido.inserted_at} ==
               {i.tipo, i.estado, i.descripcion, i.inserted_at}

      # En particular `updated_at`: la hora en que se subió la foto no se anota
      assert Repo.get!(Incident, i.id).updated_at == i.updated_at
    end

    test "otra cuenta no puede subir foto a un reporte ajeno", %{incident: i} do
      intruso = register!()

      assert Evidence.attach_photo(intruso, i.id, clean()) == {:error, :not_author}

      refute flag(i)
      assert Disk.get(i.id) == {:error, :not_found}
    end

    test "un reporte sin autor (de la siembra) no recibe fotos de nadie", %{author: a} do
      {:ok, :created, sin_autor} =
        Incidents.create_incident(
          %{"tipo" => "robo", "lat" => -16.4, "lng" => -71.53},
          Ecto.UUID.generate()
        )

      assert Evidence.attach_photo(a, sin_autor.id, clean()) == {:error, :not_author}
    end

    test "una sola foto por reporte; la primera se conserva", %{author: a, incident: i} do
      {:ok, _} = Evidence.attach_photo(a, i.id, clean())

      assert Evidence.attach_photo(a, i.id, fixture("progresiva")) == {:error, :photo_exists}
      assert Disk.get(i.id) == {:ok, clean()}
    end

    test "un reporte que no existe, o un id que no es UUID", %{author: a} do
      assert Evidence.attach_photo(a, Ecto.UUID.generate(), clean()) == {:error, :not_found}

      for malo <- ["abc", "../../etc/passwd", "", nil, 123] do
        assert Evidence.attach_photo(a, malo, clean()) == {:error, :not_found}, inspect(malo)
      end
    end

    test "un reporte descartado ya no recibe fotos", %{author: a, incident: i} do
      i |> Ecto.Changeset.change(estado: :descartado) |> Repo.update!()

      assert Evidence.attach_photo(a, i.id, clean()) == {:error, :not_found}
    end

    test "una foto con metadatos se rechaza y no se guarda nada", %{author: a, incident: i} do
      assert Evidence.attach_photo(a, i.id, fixture("con_exif_gps")) ==
               {:error, {:invalid_photo, :has_metadata}}

      refute flag(i)
      assert Disk.get(i.id) == {:error, :not_found}
    end

    test "algo que no es un JPEG se rechaza", %{author: a, incident: i} do
      assert Evidence.attach_photo(a, i.id, "no soy una foto") ==
               {:error, {:invalid_photo, :not_jpeg}}
    end

    test "mide el tamaño antes que cualquier otra cosa", %{author: a, incident: i} do
      grande = clean() <> :binary.copy(<<0>>, Evidence.max_bytes())

      assert Evidence.attach_photo(a, i.id, grande) == {:error, :photo_too_large}
      refute flag(i)
    end

    test "justo en el límite todavía entra (si es una foto válida)", %{author: a, incident: i} do
      assert byte_size(clean()) < Evidence.max_bytes()
      assert {:ok, _} = Evidence.attach_photo(a, i.id, clean())
    end

    test "si el almacenamiento falla, el reporte queda sin foto y se puede reintentar", %{
      author: a,
      incident: i
    } do
      assert Evidence.attach_photo(a, i.id, clean(), store: FailingStore) == {:error, :storage}

      refute flag(i)
      assert {:ok, _} = Evidence.attach_photo(a, i.id, clean())
    end

    test "un archivo huérfano de un intento anterior no impide subir la foto", %{
      author: a,
      incident: i
    } do
      # Quedó el archivo pero la base nunca llegó a marcar el reporte
      :ok = Disk.put(i.id, "huérfano")

      assert {:ok, _} = Evidence.attach_photo(a, i.id, clean())
      assert Disk.get(i.id) == {:ok, clean()}
    end

    test "con cinco subidas a la vez gana una sola", %{author: a, incident: i} do
      resultados =
        1..5
        |> Task.async_stream(fn _ -> Evidence.attach_photo(a, i.id, clean()) end,
          max_concurrency: 5
        )
        |> Enum.map(fn {:ok, r} -> r end)

      assert Enum.count(resultados, &match?({:ok, _}, &1)) == 1
      assert Enum.count(resultados, &(&1 == {:error, :photo_exists})) == 4
    end
  end

  describe "fetch_photo/1" do
    test "devuelve la foto de un reporte que la tiene", %{author: a, incident: i} do
      {:ok, _} = Evidence.attach_photo(a, i.id, clean())

      assert Evidence.fetch_photo(i.id) == {:ok, clean()}
    end

    test "un reporte sin foto", %{incident: i} do
      assert Evidence.fetch_photo(i.id) == {:error, :not_found}
    end

    test "un reporte que no existe o un id inválido" do
      assert Evidence.fetch_photo(Ecto.UUID.generate()) == {:error, :not_found}

      for malo <- ["abc", "../../etc/passwd", "", nil] do
        assert Evidence.fetch_photo(malo) == {:error, :not_found}, inspect(malo)
      end
    end

    test "un reporte descartado deja de mostrar su foto", %{author: a, incident: i} do
      {:ok, _} = Evidence.attach_photo(a, i.id, clean())
      i |> Ecto.Changeset.change(estado: :descartado) |> Repo.update!()

      assert Evidence.fetch_photo(i.id) == {:error, :not_found}
    end

    test "un archivo huérfano (la base nunca lo marcó) no se sirve", %{incident: i} do
      :ok = Disk.put(i.id, clean())

      refute flag(i)
      assert Evidence.fetch_photo(i.id) == {:error, :not_found}
    end

    test "si la base dice que hay foto pero el archivo se perdió", %{incident: i} do
      i |> Ecto.Changeset.change(tiene_foto: true) |> Repo.update!()

      assert Evidence.fetch_photo(i.id) == {:error, :not_found}
    end
  end
end
