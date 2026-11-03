defmodule Civic.IncidentsTest do
  use Civic.DataCase, async: true

  alias Civic.Incidents
  alias Civic.Incidents.Incident

  @valid %{
    "tipo" => "robo",
    "lat" => -16.3963,
    "lng" => -71.5340,
    "descripcion" => "Me robaron el celular"
  }

  defp key, do: Ecto.UUID.generate()

  describe "create_incident/2" do
    test "crea un incidente válido en estado sin_verificar" do
      assert {:ok, :created, inc} = Incidents.create_incident(@valid, key())
      assert inc.estado == :sin_verificar
      assert inc.tipo == :robo
      assert Incident.coords(inc) == {-16.3963, -71.5340}
    end

    test "rechaza tipo desconocido" do
      attrs = %{@valid | "tipo" => "ovni"}
      assert {:error, cs} = Incidents.create_incident(attrs, key())
      assert %{tipo: [_]} = errors_on(cs)
    end

    test "rechaza ubicación fuera de Arequipa" do
      attrs = %{@valid | "lat" => -12.05, "lng" => -77.04}
      assert {:error, cs} = Incidents.create_incident(attrs, key())
      assert errors_on(cs).ubicacion == ["La ubicación debe estar dentro de Arequipa"]
    end

    test "exige lat y lng" do
      attrs = Map.drop(@valid, ["lat", "lng"])
      assert {:error, cs} = Incidents.create_incident(attrs, key())
      errors = errors_on(cs)
      assert errors.lat == ["can't be blank"]
      assert errors.lng == ["can't be blank"]
    end

    test "descripción con solo espacios se guarda como nil" do
      attrs = %{@valid | "descripcion" => "   "}
      assert {:ok, :created, inc} = Incidents.create_incident(attrs, key())
      assert inc.descripcion == nil
    end

    test "descripción de 501 caracteres es inválida" do
      attrs = %{@valid | "descripcion" => String.duplicate("a", 501)}
      assert {:error, cs} = Incidents.create_incident(attrs, key())
      assert %{descripcion: [_]} = errors_on(cs)
    end

    test "misma idempotency_key devuelve el mismo incidente" do
      k = key()
      assert {:ok, :created, inc1} = Incidents.create_incident(@valid, k)
      assert {:ok, :existing, inc2} = Incidents.create_incident(@valid, k)
      assert inc2.id == inc1.id
      assert Repo.aggregate(Incident, :count) == 1
    end
  end

  describe "list_recent/2" do
    @bbox {-71.54, -16.40, -71.53, -16.39}

    defp insert_incident(lat, lng, inserted_at \\ DateTime.utc_now()) do
      Repo.insert!(%Incident{
        tipo: :robo,
        ubicacion: %Geo.Point{coordinates: {lng, lat}, srid: 4326},
        idempotency_key: key(),
        inserted_at: inserted_at,
        updated_at: inserted_at
      })
    end

    defp hours_ago(h), do: DateTime.add(DateTime.utc_now(), -h, :hour)

    test "filtra por bbox" do
      dentro = insert_incident(-16.395, -71.535)
      _fuera = insert_incident(-16.45, -71.60)

      assert [encontrado] = Incidents.list_recent(@bbox, hours_ago(24))
      assert encontrado.id == dentro.id
    end

    test "excluye los más antiguos que since" do
      reciente = insert_incident(-16.395, -71.535, hours_ago(1))
      _viejo = insert_incident(-16.395, -71.535, hours_ago(25))

      assert [encontrado] = Incidents.list_recent(@bbox, hours_ago(24))
      assert encontrado.id == reciente.id
    end

    test "ordena del más nuevo al más antiguo" do
      viejo = insert_incident(-16.395, -71.535, hours_ago(5))
      nuevo = insert_incident(-16.395, -71.535, hours_ago(1))

      assert [a, b] = Incidents.list_recent(@bbox, hours_ago(24))
      assert {a.id, b.id} == {nuevo.id, viejo.id}
    end

    test "devuelve como máximo 500 incidentes" do
      now = DateTime.utc_now()

      rows =
        for _ <- 1..501 do
          %{
            id: Ecto.UUID.generate(),
            tipo: :robo,
            estado: :sin_verificar,
            ubicacion: %Geo.Point{coordinates: {-71.535, -16.395}, srid: 4326},
            idempotency_key: Ecto.UUID.generate(),
            inserted_at: now,
            updated_at: now
          }
        end

      Repo.insert_all(Incident, rows)
      assert length(Incidents.list_recent(@bbox, hours_ago(24))) == 500
    end
  end
end
