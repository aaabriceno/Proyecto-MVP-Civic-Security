defmodule Civic.Incidents.HeatTest do
  use Civic.DataCase, async: true

  alias Civic.Incidents.Heat
  alias Civic.Incidents.Incident
  alias Civic.Repo

  # 0,01° de ancho: la celda resultante es de 0,0005° (~55 m)
  @bbox {-71.54, -16.40, -71.53, -16.39}

  defp insert(lat, lng, opts \\ []) do
    at = Keyword.get(opts, :at, DateTime.utc_now())

    Repo.insert!(%Incident{
      tipo: Keyword.get(opts, :tipo, :robo),
      estado: Keyword.get(opts, :estado, :sin_verificar),
      ubicacion: %Geo.Point{coordinates: {lng, lat}, srid: 4326},
      idempotency_key: Ecto.UUID.generate(),
      inserted_at: at,
      updated_at: at
    })
  end

  defp hours_ago(h), do: DateTime.add(DateTime.utc_now(), -round(h * 3600), :second)

  describe "parse_window/1" do
    test "acepta 1h, 24h y 7d" do
      assert Heat.parse_window("1h") == {:ok, :hora}
      assert Heat.parse_window("24h") == {:ok, :dia}
      assert Heat.parse_window("7d") == {:ok, :semana}
    end

    test "sin valor usa 24h" do
      assert Heat.parse_window(nil) == {:ok, :dia}
    end

    test "rechaza cualquier otra cosa" do
      for malo <- ["", "2h", "24H", "semana", "1h; drop table", 24, %{}] do
        assert Heat.parse_window(malo) == {:error, :invalid_window}, inspect(malo)
      end
    end
  end

  describe "cell_size/1" do
    test "una zona chica da celdas chicas y una grande, celdas grandes" do
      assert Heat.cell_size(@bbox) == 0.0005
      assert Heat.cell_size({-71.75, -16.60, -71.40, -16.25}) == 0.02
    end

    test "siempre devuelve uno de los tamaños permitidos" do
      permitidos = [0.0005, 0.001, 0.0025, 0.005, 0.01, 0.02, 0.05]

      for ancho <- [0.0001, 0.003, 0.02, 0.07, 0.2, 1.0, 50.0] do
        assert Heat.cell_size({-71.0, -16.0, -71.0 + ancho, -15.0}) in permitidos
      end
    end
  end

  describe "compute/2" do
    test "junta los incidentes de una misma celda y cuenta por tipo" do
      insert(-16.3951, -71.5351)
      insert(-16.3949, -71.5349)
      insert(-16.3952, -71.5348)
      insert(-16.3948, -71.5352, tipo: :pelea_colegio)

      assert %{cells: [celda], cell_deg: 0.0005} = Heat.compute(@bbox, :dia)

      assert celda.count == 4
      assert celda.tipos == %{robo: 3, pelea_colegio: 1}
      assert_in_delta celda.lat, -16.395, 0.0003
      assert_in_delta celda.lng, -71.535, 0.0003
    end

    test "celdas distintas quedan separadas, la más activa primero" do
      insert(-16.392, -71.532)
      for _ <- 1..3, do: insert(-16.398, -71.538)

      assert %{cells: [mayor, menor]} = Heat.compute(@bbox, :dia)

      assert {mayor.count, menor.count} == {3, 1}
    end

    test "no cuenta los descartados" do
      insert(-16.395, -71.535, estado: :descartado)
      insert(-16.395, -71.535, estado: :descartado)

      assert %{cells: []} = Heat.compute(@bbox, :dia)

      insert(-16.395, -71.535, estado: :verificado)
      assert %{cells: [%{count: 1}]} = Heat.compute(@bbox, :dia)
    end

    test "respeta el bbox" do
      insert(-16.395, -71.535)
      insert(-16.45, -71.60)

      assert %{cells: [%{count: 1}]} = Heat.compute(@bbox, :dia)
    end

    test "la ventana de 1 h solo cuenta lo último" do
      insert(-16.395, -71.535, at: hours_ago(0.5))
      insert(-16.395, -71.535, at: hours_ago(2))

      assert %{cells: [%{count: 1}]} = Heat.compute(@bbox, :hora)
    end

    test "la ventana de 24 h cuenta lo del día y no lo de hace 2 días" do
      insert(-16.395, -71.535, at: hours_ago(23))
      insert(-16.395, -71.535, at: hours_ago(49))

      assert %{cells: [%{count: 1}]} = Heat.compute(@bbox, :dia)
    end

    test "la ventana de 7 días cuenta lo de la semana y no lo de hace 8 días" do
      insert(-16.395, -71.535, at: hours_ago(24 * 6))
      insert(-16.395, -71.535, at: hours_ago(24 * 8))

      assert %{cells: [%{count: 1}]} = Heat.compute(@bbox, :semana)
    end

    test "la franja horaria más frecuente es en hora de Perú (UTC-5), de 3 en 3 horas" do
      # 23:30 UTC = 18:30 en Lima -> franja 18:00 a 21:00
      dia = DateTime.new!(Date.add(Date.utc_today(), -2), ~T[23:30:00.000000], "Etc/UTC")
      insert(-16.395, -71.535, at: dia)
      insert(-16.395, -71.535, at: DateTime.add(dia, 600, :second))
      # 14:00 UTC = 09:00 en Lima -> franja 09:00 a 12:00
      insert(-16.395, -71.535, at: DateTime.add(dia, -9 * 3600 - 1800, :second))

      assert %{cells: [celda]} = Heat.compute(@bbox, :semana)
      assert celda.franja == {18, 21}
    end

    test "devuelve como máximo 400 celdas" do
      now = DateTime.utc_now()

      rows =
        for i <- 0..449 do
          %{
            id: Ecto.UUID.generate(),
            tipo: :robo,
            estado: :sin_verificar,
            # Cada punto en su propia celda de 0,0005°, una sobre otra en la misma columna
            ubicacion: %Geo.Point{
              coordinates: {-71.535, -16.5 + i * 0.0005},
              srid: 4326
            },
            idempotency_key: Ecto.UUID.generate(),
            inserted_at: now,
            updated_at: now
          }
        end

      Repo.insert_all(Incident, rows)

      assert %{cells: celdas} = Heat.compute({-71.54, -16.50, -71.53, -16.27}, :dia)
      assert length(celdas) == 400
    end

    test "sin incidentes devuelve una lista vacía" do
      assert %{cells: []} = Heat.compute(@bbox, :dia)
    end

    test "una celda solo expone posición, cuenta, tipos y franja" do
      insert(-16.395, -71.535)

      assert %{cells: [celda]} = Heat.compute(@bbox, :dia)

      assert celda |> Map.keys() |> Enum.sort() == [:count, :franja, :lat, :lng, :tipos]
    end
  end
end
