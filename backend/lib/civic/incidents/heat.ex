defmodule Civic.Incidents.Heat do
  @moduledoc """
  Mapa de calor: cuántos incidentes hay por zona.

  El mapa se parte en una cuadrícula y se cuenta cuántos incidentes cayen en cada
  celda. El tamaño de la celda depende de cuánto se está mirando (`cell_size/1`):
  con la ciudad entera son celdas de ~2 km y al acercarse bajan hasta ~55 m. Cada
  celda trae su posición, la cuenta, cuántos son de cada tipo y la franja de 3
  horas (hora de Perú) en que más se reporta.

  Es una consulta agregada: no devuelve incidentes individuales, ni autores, ni
  horas exactas. No cuenta los incidentes descartados.
  """

  import Ecto.Query

  alias Civic.Incidents.Incident
  alias Civic.Repo

  # Lado de la celda en grados (0,0005° ~ 55 m). Se elige el menor que no deje
  # más de ~24 celdas a lo ancho de la zona que se mira.
  @tamanos [0.0005, 0.001, 0.0025, 0.005, 0.01, 0.02, 0.05]
  @celdas_a_lo_ancho 24

  @max_celdas 400

  # Perú no tiene horario de verano: siempre UTC-5
  @zona_horaria "America/Lima"
  @horas_por_franja 3

  @type ventana :: :hora | :dia | :semana
  @type celda :: %{
          lat: float(),
          lng: float(),
          count: pos_integer(),
          tipos: %{atom() => pos_integer()},
          franja: {0..21, 3..24}
        }

  @doc "Interpreta el parámetro `ventana` de la API: `1h`, `24h` o `7d` (por omisión, `24h`)."
  @spec parse_window(term()) :: {:ok, ventana()} | {:error, :invalid_window}
  def parse_window(nil), do: {:ok, :dia}
  def parse_window("1h"), do: {:ok, :hora}
  def parse_window("24h"), do: {:ok, :dia}
  def parse_window("7d"), do: {:ok, :semana}
  def parse_window(_), do: {:error, :invalid_window}

  @doc "Lado de la celda, en grados, para la zona que se está mirando."
  @spec cell_size(Civic.Incidents.Bbox.t()) :: float()
  def cell_size({min_lng, _min_lat, max_lng, _max_lat}) do
    ideal = (max_lng - min_lng) / @celdas_a_lo_ancho
    Enum.find(@tamanos, List.last(@tamanos), &(&1 >= ideal))
  end

  @doc """
  Las celdas con incidentes dentro de `bbox` en la `ventana` de tiempo, de la más
  a la menos activa (máximo #{@max_celdas}).
  """
  @spec compute(Civic.Incidents.Bbox.t(), ventana()) :: %{cell_deg: float(), cells: [celda()]}
  def compute({min_lng, min_lat, max_lng, max_lat} = bbox, ventana) do
    tamano = cell_size(bbox)
    since = DateTime.add(DateTime.utc_now(), -segundos(ventana), :second)

    # Una subconsulta para calcular la celda UNA vez: si se repitiera en el
    # GROUP BY y en el SELECT, PostgreSQL vería dos parámetros distintos.
    base =
      from i in Incident,
        where: i.inserted_at > ^since and i.estado != :descartado,
        where:
          fragment(
            "ST_Intersects(?, ST_MakeEnvelope(?, ?, ?, ?, 4326)::geography)",
            i.ubicacion,
            ^min_lng,
            ^min_lat,
            ^max_lng,
            ^max_lat
          ),
        select: %{
          celda: fragment("ST_SnapToGrid(?::geometry, ?::float8)", i.ubicacion, ^tamano),
          tipo: i.tipo,
          banda:
            fragment(
              "(floor(extract(hour from (? at time zone 'UTC') at time zone ?) / ?))::int",
              i.inserted_at,
              ^@zona_horaria,
              ^@horas_por_franja
            )
        }

    filas =
      Repo.all(
        from c in subquery(base),
          group_by: [c.celda, c.tipo, c.banda],
          select: %{
            lng: fragment("ST_X(?)", c.celda),
            lat: fragment("ST_Y(?)", c.celda),
            tipo: c.tipo,
            banda: c.banda,
            n: count()
          }
      )

    celdas =
      filas
      |> Enum.group_by(&{&1.lat, &1.lng})
      |> Enum.map(fn {{lat, lng}, grupo} -> celda(lat, lng, grupo) end)
      |> Enum.sort_by(&{-&1.count, &1.lat, &1.lng})
      |> Enum.take(@max_celdas)

    %{cell_deg: tamano, cells: celdas}
  end

  defp celda(lat, lng, filas) do
    %{
      lat: Float.round(lat, 6),
      lng: Float.round(lng, 6),
      count: suma(filas),
      tipos: filas |> Enum.group_by(& &1.tipo) |> Map.new(fn {t, fs} -> {t, suma(fs)} end),
      franja: franja_mas_frecuente(filas)
    }
  end

  defp suma(filas), do: Enum.reduce(filas, 0, &(&1.n + &2))

  # La de más incidentes; si empatan, la más temprana
  defp franja_mas_frecuente(filas) do
    banda =
      filas
      |> Enum.group_by(& &1.banda)
      |> Enum.map(fn {banda, fs} -> {banda, suma(fs)} end)
      |> Enum.max_by(fn {banda, n} -> {n, -banda} end)
      |> elem(0)

    {banda * @horas_por_franja, (banda + 1) * @horas_por_franja}
  end

  defp segundos(:hora), do: 3_600
  defp segundos(:dia), do: 24 * 3_600
  defp segundos(:semana), do: 7 * 24 * 3_600
end
