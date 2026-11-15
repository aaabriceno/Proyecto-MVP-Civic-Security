defmodule Civic.IncidentsTest do
  use Civic.DataCase, async: true

  alias Civic.Accounts
  alias Civic.Incidents
  alias Civic.Incidents.Incident
  alias Civic.Privacy
  alias Civic.Repo

  @valid %{
    "tipo" => "robo",
    "lat" => -16.3963,
    "lng" => -71.5340,
    "descripcion" => "Me robaron el celular"
  }

  defp key, do: Ecto.UUID.generate()

  defp create_user!(nivel \\ :invitado) do
    {:ok, user} =
      Accounts.register(%{
        "alias" => "Cuenta-#{rem(System.unique_integer([:positive]), 1_000_000)}",
        "password" => "una contraseña larga y segura",
        "acepta_consentimiento" => true
      })

    if nivel == :verificado,
      do: user |> Ecto.Changeset.change(nivel: :verificado) |> Repo.update!(),
      else: user
  end

  describe "create_incident/2" do
    test "crea un incidente válido en estado sin_verificar" do
      assert {:ok, :created, inc} = Incidents.create_incident(@valid, key())
      assert inc.estado == :sin_verificar
      assert inc.tipo == :robo
      assert Incident.coords(inc) == {-16.3963, -71.5340}
    end

    test "acepta los seis tipos, incluido otro" do
      for tipo <- ~w(robo agresion_mujer maltrato_animal pelea_colegio actividad_sospechosa otro) do
        assert {:ok, :created, inc} = Incidents.create_incident(%{@valid | "tipo" => tipo}, key())
        assert Atom.to_string(inc.tipo) == tipo
      end
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

    test "rechaza caracteres de control y de dirección de texto en la descripción" do
      peligrosos = [
        "a\u0000b",
        "alarma\u0007",
        "texto \u202Eoculto",
        "texto \u2066aislado\u2069"
      ]

      for texto <- peligrosos do
        attrs = %{@valid | "descripcion" => texto}
        assert {:error, cs} = Incidents.create_incident(attrs, key())
        assert errors_on(cs).descripcion == ["contiene caracteres no permitidos"]
      end
    end

    test "rechaza datos personales en la descripción (DNI, teléfono, correo, enlaces)" do
      con_datos = [
        "El sujeto dijo que su DNI es 70123456",
        "llamen al 987654321",
        "su celular: 987 654 321",
        "su celular: 987-654-321",
        "mi número es +51 987 654 321",
        "escríbeme a persona@correo.com",
        "mira el video en https://ejemplo.com/video",
        "más info en www.ejemplo.pe"
      ]

      for texto <- con_datos do
        attrs = %{@valid | "descripcion" => texto}
        assert {:error, cs} = Incidents.create_incident(attrs, key()), "debió rechazar: #{texto}"

        assert errors_on(cs).descripcion ==
                 ["no escribas datos personales (DNI, teléfonos, correos ni enlaces)"]
      end
    end

    test "no confunde datos corrientes con datos personales" do
      sin_datos = [
        "Av. Ejército 710, dos sujetos en moto",
        "Fue a las 23:45, eran 3 hombres y 2 motos",
        "Robaron 1500 soles y 2 celulares en la cuadra 12",
        "Placa ABC-123, huyeron hacia el puente",
        "Ocurrió el 05/11/2026 alrededor de las 10",
        "Calle 28 de Julio 1234, frente al banco"
      ]

      for texto <- sin_datos do
        attrs = %{@valid | "descripcion" => texto}

        assert {:ok, :created, _} = Incidents.create_incident(attrs, key()),
               "no debió rechazar: #{texto}"
      end
    end

    test "permite saltos de línea y tildes en la descripción" do
      attrs = %{@valid | "descripcion" => "Línea 1\nLínea 2\tcon ñ y ¿qué?"}
      assert {:ok, :created, inc} = Incidents.create_incident(attrs, key())
      assert inc.descripcion == "Línea 1\nLínea 2\tcon ñ y ¿qué?"
    end

    test "la misma idempotency_key con otro contenido es un conflicto" do
      k = key()
      assert {:ok, :created, _} = Incidents.create_incident(@valid, k)

      assert {:error, :idempotency_conflict} =
               Incidents.create_incident(%{@valid | "tipo" => "pelea_colegio"}, k)

      assert {:error, :idempotency_conflict} =
               Incidents.create_incident(%{@valid | "lat" => -16.40}, k)

      assert Repo.aggregate(Incident, :count) == 1
    end

    test "misma idempotency_key devuelve el mismo incidente" do
      k = key()
      assert {:ok, :created, inc1} = Incidents.create_incident(@valid, k)
      assert {:ok, :existing, inc2} = Incidents.create_incident(@valid, k)
      assert inc2.id == inc1.id
      assert Repo.aggregate(Incident, :count) == 1
    end
  end

  describe "report_incident/3 (reporte con cuenta)" do
    test "crea el incidente y guarda el token del autor, calculado por incidente" do
      user = create_user!()

      assert {:ok, :created, inc} = Incidents.report_incident(user, @valid, key())

      assert inc.reporter_token == Privacy.reporter_token(user.id, inc.id)
      assert byte_size(inc.reporter_token) == 32
    end

    test "dos reportes de la misma cuenta no se pueden enlazar entre sí" do
      user = create_user!()

      {:ok, :created, uno} = Incidents.report_incident(user, @valid, key())
      {:ok, :created, dos} = Incidents.report_incident(user, @valid, key())

      refute uno.reporter_token == dos.reporter_token
    end

    test "la base de datos no guarda el id de la cuenta junto al incidente" do
      user = create_user!()
      {:ok, :created, inc} = Incidents.report_incident(user, @valid, key())

      %{columns: columnas, rows: [fila]} =
        Repo.query!("select * from incidentes where id = $1", [Ecto.UUID.dump!(inc.id)])

      refute "usuario_id" in columnas
      refute "cuenta_id" in columnas
      {:ok, id_binario} = Ecto.UUID.dump(user.id)
      refute Enum.any?(fila, &(&1 == id_binario or &1 == user.id))
    end

    test "repetir la misma key con el mismo contenido devuelve el mismo incidente y no gasta cupo" do
      user = create_user!()
      k = key()

      assert {:ok, :created, uno} = Incidents.report_incident(user, @valid, k)

      # Un cupo de 3: si la repetición gastara cupo, el 3.º reporte distinto fallaría
      for _ <- 1..5 do
        assert {:ok, :existing, repetido} = Incidents.report_incident(user, @valid, k)
        assert repetido.id == uno.id
      end

      assert {:ok, :created, _} = Incidents.report_incident(user, @valid, key())
      assert {:ok, :created, _} = Incidents.report_incident(user, @valid, key())
    end

    test "otra cuenta que usa la misma key recibe conflicto, no el incidente ajeno" do
      k = key()
      {:ok, :created, _} = Incidents.report_incident(create_user!(), @valid, k)

      assert {:error, :idempotency_conflict} =
               Incidents.report_incident(create_user!(), @valid, k)
    end

    test "una key de un incidente sin autor (siembra) tampoco se puede reclamar" do
      k = key()
      {:ok, :created, _} = Incidents.create_incident(@valid, k)

      assert {:error, :idempotency_conflict} =
               Incidents.report_incident(create_user!(), @valid, k)
    end

    test "una cuenta sin verificar tiene un cupo de 3 reportes por día" do
      user = create_user!()

      for _ <- 1..3,
          do: assert({:ok, :created, _} = Incidents.report_incident(user, @valid, key()))

      assert {:error, {:quota_exceeded, retry_ms}} =
               Incidents.report_incident(user, @valid, key())

      assert is_integer(retry_ms) and retry_ms > 0
    end

    test "una cuenta verificada tiene un cupo de 10 reportes por día" do
      user = create_user!(:verificado)

      for _ <- 1..10,
          do: assert({:ok, :created, _} = Incidents.report_incident(user, @valid, key()))

      assert {:error, {:quota_exceeded, _}} = Incidents.report_incident(user, @valid, key())
    end

    test "el cupo es de cada cuenta: agotar el de una no afecta a otra" do
      una = create_user!()
      otra = create_user!()

      for _ <- 1..3, do: {:ok, :created, _} = Incidents.report_incident(una, @valid, key())
      assert {:error, {:quota_exceeded, _}} = Incidents.report_incident(una, @valid, key())

      assert {:ok, :created, _} = Incidents.report_incident(otra, @valid, key())
    end

    test "un reporte inválido no gasta cupo" do
      user = create_user!()

      for _ <- 1..5 do
        assert {:error, %Ecto.Changeset{}} =
                 Incidents.report_incident(user, %{@valid | "lat" => 40.0}, key())
      end

      for _ <- 1..3,
          do: assert({:ok, :created, _} = Incidents.report_incident(user, @valid, key()))
    end

    test "un incidente sin cuenta (create_incident/2) no guarda token" do
      assert {:ok, :created, inc} = Incidents.create_incident(@valid, key())
      assert inc.reporter_token == nil
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
