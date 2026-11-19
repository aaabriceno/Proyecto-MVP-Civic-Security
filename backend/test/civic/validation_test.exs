defmodule Civic.ValidationTest do
  use Civic.DataCase, async: true

  alias Civic.Accounts
  alias Civic.Accounts.Verification
  alias Civic.Incidents
  alias Civic.Incidents.Incident
  alias Civic.Privacy
  alias Civic.Repo
  alias Civic.Validation

  # El reporte está en (-16.4, -71.53). Un grado de latitud son ~111,2 km, así que
  # 0,008° son ~890 m (dentro del radio de 1 km) y 0,0095° son ~1056 m (fuera).
  @lat -16.4
  @lng -71.53
  @cerca {@lat + 0.008, @lng}
  @lejos {@lat + 0.0095, @lng}

  defp register! do
    {:ok, user} =
      Accounts.register(%{
        "alias" => "Votante-#{System.unique_integer([:positive])}",
        "password" => "una contraseña larga y segura",
        "acepta_consentimiento" => true
      })

    user
  end

  # Un DNI distinto en cada llamada: el índice único los bloquearía entre sí
  defp dni do
    [:positive]
    |> System.unique_integer()
    |> rem(100_000_000)
    |> Integer.to_string()
    |> String.pad_leading(8, "0")
  end

  defp verified! do
    {:ok, user} = Verification.verify_dni(register!(), dni())
    user
  end

  defp report!(author) do
    {:ok, :created, incident} =
      Incidents.report_incident(
        author,
        %{"tipo" => "robo", "lat" => @lat, "lng" => @lng},
        Ecto.UUID.generate()
      )

    incident
  end

  defp vote(user, incident, valor, {lat, lng} = _donde \\ @cerca, opts \\ []),
    do: Validation.vote(user, incident.id, valor, lat, lng, opts)

  defp fresh(incident), do: Repo.get!(Incident, incident.id)

  setup do
    author = verified!()
    {:ok, author: author, incident: report!(author)}
  end

  describe "vote/5: confirmar" do
    test "suma una confirmación y devuelve el reporte actualizado", %{incident: incident} do
      assert {:ok, %Incident{} = updated} = vote(verified!(), incident, "confirmo")

      assert updated.id == incident.id
      assert updated.confirmaciones == 1
      assert updated.falsos == 0
      assert updated.estado == :sin_verificar
      assert fresh(incident).confirmaciones == 1
    end

    test "con 3 cuentas distintas el reporte pasa a Verificado", %{incident: incident} do
      assert {:ok, %{estado: :sin_verificar}} = vote(verified!(), incident, "confirmo")
      assert {:ok, %{estado: :sin_verificar}} = vote(verified!(), incident, "confirmo")

      assert {:ok, %{estado: :verificado, confirmaciones: 3}} =
               vote(verified!(), incident, "confirmo")

      assert fresh(incident).estado == :verificado
    end

    test "el umbral se puede cambiar (para una demostración con pocos dispositivos)", %{
      incident: incident
    } do
      assert {:ok, %{estado: :sin_verificar}} =
               vote(verified!(), incident, "confirmo", @cerca, threshold: 2)

      assert {:ok, %{estado: :verificado, confirmaciones: 2}} =
               vote(verified!(), incident, "confirmo", @cerca, threshold: 2)
    end
  end

  describe "vote/5: es falso" do
    test "suma un falso sin cambiar el estado", %{incident: incident} do
      assert {:ok, %{falsos: 1, confirmaciones: 0, estado: :sin_verificar}} =
               vote(verified!(), incident, "falso")
    end

    test "con 3 cuentas distintas el reporte pasa a Descartado", %{incident: incident} do
      assert {:ok, _} = vote(verified!(), incident, "falso")
      assert {:ok, _} = vote(verified!(), incident, "falso")
      assert {:ok, %{estado: :descartado, falsos: 3}} = vote(verified!(), incident, "falso")

      assert fresh(incident).estado == :descartado
    end

    test "los votos mezclados no alcanzan: 2 confirmaciones y 2 falsos siguen sin verificar", %{
      incident: incident
    } do
      for valor <- ["confirmo", "falso", "confirmo", "falso"] do
        assert {:ok, %{estado: :sin_verificar}} = vote(verified!(), incident, valor)
      end

      reporte = fresh(incident)
      assert {reporte.confirmaciones, reporte.falsos} == {2, 2}
    end
  end

  describe "vote/5: reglas" do
    test "una cuenta sin verificar no puede votar", %{incident: incident} do
      assert vote(register!(), incident, "confirmo") == {:error, :not_verified}
      assert fresh(incident).confirmaciones == 0
    end

    test "el autor no puede votar su propio reporte", %{author: author, incident: incident} do
      assert vote(author, incident, "confirmo") == {:error, :own_report}
      assert vote(author, incident, "falso") == {:error, :own_report}

      reporte = fresh(incident)
      assert {reporte.confirmaciones, reporte.falsos} == {0, 0}
    end

    test "un reporte sin autor (de ejemplo) sí se puede votar" do
      {:ok, :created, ejemplo} =
        Incidents.create_incident(
          %{"tipo" => "robo", "lat" => @lat, "lng" => @lng},
          Ecto.UUID.generate()
        )

      assert {:ok, %{confirmaciones: 1}} = vote(verified!(), ejemplo, "confirmo")
    end

    test "una cuenta vota una sola vez y no puede cambiar su voto", %{incident: incident} do
      votante = verified!()
      assert {:ok, %{confirmaciones: 1}} = vote(votante, incident, "confirmo")

      assert vote(votante, incident, "confirmo") == {:error, :already_voted}
      assert vote(votante, incident, "falso") == {:error, :already_voted}

      reporte = fresh(incident)
      assert {reporte.confirmaciones, reporte.falsos} == {1, 0}
    end

    test "la misma cuenta sí puede votar en otro reporte", %{author: author} do
      votante = verified!()

      assert {:ok, _} = vote(votante, report!(author), "confirmo")
      assert {:ok, _} = vote(votante, report!(author), "confirmo")
    end

    test "hay que estar a menos de 1 km del lugar", %{incident: incident} do
      assert vote(verified!(), incident, "confirmo", @lejos) == {:error, :too_far}
      assert fresh(incident).confirmaciones == 0

      assert {:ok, _} = vote(verified!(), incident, "confirmo", @cerca)
    end

    test "el radio se puede cambiar", %{incident: incident} do
      assert {:ok, _} = vote(verified!(), incident, "confirmo", @lejos, radius_m: 2_000)
    end

    test "un voto rechazado por lejos no gasta el voto de la cuenta", %{incident: incident} do
      votante = verified!()

      assert vote(votante, incident, "confirmo", @lejos) == {:error, :too_far}
      assert {:ok, _} = vote(votante, incident, "confirmo", @cerca)
    end

    test "un reporte ya verificado o descartado no recibe más votos", %{incident: incident} do
      for _ <- 1..3, do: {:ok, _} = vote(verified!(), incident, "confirmo")

      assert vote(verified!(), incident, "confirmo") == {:error, :voting_closed}
      assert vote(verified!(), incident, "falso") == {:error, :voting_closed}
      assert fresh(incident).confirmaciones == 3

      descartado = report!(verified!())
      for _ <- 1..3, do: {:ok, _} = vote(verified!(), descartado, "falso")
      assert vote(verified!(), descartado, "confirmo") == {:error, :voting_closed}
    end
  end

  describe "vote/5: entradas inválidas" do
    test "un reporte que no existe, o un id mal formado, da :not_found" do
      user = verified!()

      assert Validation.vote(user, Ecto.UUID.generate(), "confirmo", @lat, @lng) ==
               {:error, :not_found}

      for malo <- ["no-es-uuid", "", nil, 123, <<0::128>>] do
        assert Validation.vote(user, malo, "confirmo", @lat, @lng) == {:error, :not_found},
               inspect(malo)
      end
    end

    test "el valor solo puede ser confirmo o falso", %{incident: incident} do
      user = verified!()

      for malo <- ["si", "CONFIRMO", "", nil, :confirmo, 1, %{}] do
        assert vote(user, incident, malo) == {:error, :invalid_vote}, inspect(malo)
      end

      assert fresh(incident).confirmaciones == 0
    end

    test "la ubicación debe ser un par de números válidos", %{incident: incident} do
      user = verified!()

      for {lat, lng} <- [
            {nil, @lng},
            {@lat, nil},
            {"-16.4", "-71.5"},
            {91, 0},
            {0, 181},
            {nil, nil}
          ] do
        assert Validation.vote(user, incident.id, "confirmo", lat, lng) ==
                 {:error, :invalid_location},
               inspect({lat, lng})
      end

      assert fresh(incident).confirmaciones == 0
    end

    test "los enteros también valen como coordenadas", %{incident: incident} do
      # Un entero es un número: 0 grados queda lejos de Arequipa, no es inválido
      assert Validation.vote(verified!(), incident.id, "confirmo", 0, 0) == {:error, :too_far}
    end
  end

  describe "privacidad" do
    test "solo se guarda el token del votante, nunca el id de la cuenta", %{incident: incident} do
      votante = verified!()
      {:ok, _} = vote(votante, incident, "confirmo")

      token = Privacy.voter_token(votante.id, incident.id)

      assert %{rows: [[guardado]]} =
               Repo.query!("SELECT voter_token FROM confirmaciones WHERE incidente_id = $1", [
                 Ecto.UUID.dump!(incident.id)
               ])

      assert guardado == token

      # Ni en texto: la fila entera no menciona el id de la cuenta
      assert %{rows: [[fila]]} =
               Repo.query!(
                 "SELECT confirmaciones::text FROM confirmaciones WHERE incidente_id = $1",
                 [Ecto.UUID.dump!(incident.id)]
               )

      refute fila =~ votante.id
    end

    test "la ubicación del votante no se guarda", %{incident: incident} do
      {:ok, _} = vote(verified!(), incident, "confirmo")

      assert %{rows: columnas} =
               Repo.query!(
                 "SELECT column_name FROM information_schema.columns WHERE table_name = 'confirmaciones'",
                 []
               )

      nombres = List.flatten(columnas)
      refute Enum.any?(nombres, &(&1 in ["lat", "lng", "ubicacion", "usuario_id", "user_id"]))
    end

    test "al borrar el reporte se borran sus votos", %{incident: incident} do
      {:ok, _} = vote(verified!(), incident, "confirmo")

      Repo.delete!(fresh(incident))

      assert %{rows: [[0]]} =
               Repo.query!("SELECT count(*) FROM confirmaciones WHERE incidente_id = $1", [
                 Ecto.UUID.dump!(incident.id)
               ])
    end
  end
end
