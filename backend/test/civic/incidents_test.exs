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
end
