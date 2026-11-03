# Datos ficticios para la demo del avance 1 (NO son reportes reales).
# mix run priv/repo/seeds.exs

# Cada reporte pasa por Civic.Incidents.create_incident/2, es decir, por las
# mismas reglas de negocio que usará la API. Solo el estado y la fecha se
# ajustan después, para simular reportes de los últimos 7 días que ya pasaron
# por la validación comunitaria.

alias Civic.Repo
alias Civic.Incidents
alias Civic.Incidents.Incident
import Ecto.Query

if Mix.env() != :dev do
  raise "seeds.exs solo debe correr en desarrollo"
end

# Oculta el log SQL de depuración para que la salida se lea en la demo
Logger.configure(level: :info)

# Semilla fija: siempre se generan los mismos datos
:rand.seed(:exsss, {2026, 10, 29})

existentes = Repo.aggregate(Incident, :count)

if existentes > 0 do
  IO.puts("Borrando #{existentes} incidentes de desarrollo anteriores...")
  Repo.delete_all(Incident)
end

zonas = [
  {"UCSP - San Lázaro", -16.3963, -71.5340, 6},
  {"Plaza de Armas", -16.3989, -71.5370, 8},
  {"Yanahuara", -16.3883, -71.5414, 3},
  {"Cayma", -16.3700, -71.5450, 2},
  {"Cerro Colorado", -16.3700, -71.5600, 3},
  {"Alto Selva Alegre", -16.3750, -71.5200, 2},
  {"Miraflores", -16.3930, -71.5200, 3},
  {"Mariano Melgar", -16.4050, -71.5100, 4},
  {"Paucarpata", -16.4300, -71.5050, 3},
  {"J. L. Bustamante y Rivero", -16.4250, -71.5300, 2},
  {"Sachaca", -16.4250, -71.5650, 1},
  {"Socabaya", -16.4650, -71.5300, 1}
]

# {zona, lat, lng, peso}: más peso = más reportes (simula zonas de mayor riesgo)

descripciones = %{
  "robo" => [
    "Arrebato de celular a una estudiante en el paradero",
    "Dos sujetos en moto robaron una mochila",
    "Robo de autopartes a un auto estacionado",
    "Le quitaron la billetera a un señor al bajar del bus"
  ],
  "agresion_mujer" => [
    "Un hombre acosa a mujeres que pasan por la esquina",
    "Agresión verbal y empujones a una joven",
    "Sujeto con arma blanca amenazó a una mujer"
  ],
  "maltrato_animal" => [
    "Perro amarrado sin agua ni sombra todo el día",
    "Están golpeando a un perro callejero",
    "Gatos envenenados en el parque"
  ],
  "pelea_colegio" => [
    "Pelea entre alumnos a la salida del colegio",
    "Grupo de escolares agrediendo a otro alumno",
    "Enfrentamiento entre estudiantes de dos colegios"
  ],
  "actividad_sospechosa" => [
    "Auto sin placa dando vueltas por la cuadra",
    "Personas observando las casas y tomando fotos",
    "Sujeto merodeando los autos estacionados"
  ]
}

# Horas de Lima, con más peso en la tarde y noche
horas = Enum.flat_map(6..23, fn h -> List.duplicate(h, if(h >= 17, do: 3, else: 1)) end)

pesos_zona = Enum.flat_map(zonas, fn {_, _, _, peso} = z -> List.duplicate(z, peso) end)

estado_al_azar = fn ->
  case :rand.uniform(100) do
    n when n <= 50 -> :sin_verificar
    n when n <= 85 -> :verificado
    _ -> :descartado
  end
end

# Fecha aleatoria de los últimos 7 días (hora de Lima = UTC-5), guardada en UTC
ahora = DateTime.utc_now()
hoy_lima = ahora |> DateTime.add(-5, :hour) |> DateTime.to_date()

fecha_al_azar = fn ->
  dias = if :rand.uniform(100) <= 35, do: 0, else: :rand.uniform(6)
  hora = Enum.random(horas)
  minuto = :rand.uniform(60) - 1

  utc =
    hoy_lima
    |> Date.add(-dias)
    |> NaiveDateTime.new!(Time.new!(hora, minuto, 0))
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.add(5, :hour)

  utc = if DateTime.compare(utc, ahora) == :gt, do: DateTime.add(utc, -1, :day), else: utc
  %{utc | microsecond: {0, 6}}
end

total = 80

for _ <- 1..total do
  {_zona, lat, lng, _} = Enum.random(pesos_zona)
  tipo = descripciones |> Map.keys() |> Enum.random()

  attrs = %{
    "tipo" => tipo,
    "descripcion" => Enum.random(descripciones[tipo]),
    # ±400 m alrededor del centro de la zona
    "lat" => Float.round(lat + (:rand.uniform() - 0.5) * 0.008, 6),
    "lng" => Float.round(lng + (:rand.uniform() - 0.5) * 0.008, 6)
  }

  {:ok, :created, incidente} = Incidents.create_incident(attrs, Ecto.UUID.generate())
  fecha = fecha_al_azar.()

  Repo.update_all(from(i in Incident, where: i.id == ^incidente.id),
    set: [estado: estado_al_azar.(), inserted_at: fecha, updated_at: fecha]
  )
end

IO.puts("\n#{total} incidentes ficticios creados.\n")

IO.puts("Las reglas de negocio también rechazan datos inválidos:")

{:error, cs} =
  Incidents.create_incident(
    %{"tipo" => "robo", "lat" => -12.0464, "lng" => -77.0428},
    Ecto.UUID.generate()
  )

IO.puts(
  "  - Reporte en Lima         -> #{inspect(Ecto.Changeset.traverse_errors(cs, &elem(&1, 0)))}"
)

{:error, cs} =
  Incidents.create_incident(
    %{"tipo" => "ovni", "lat" => -16.3963, "lng" => -71.5340},
    Ecto.UUID.generate()
  )

IO.puts(
  "  - Tipo \"ovni\"             -> #{inspect(Ecto.Changeset.traverse_errors(cs, &elem(&1, 0)))}"
)

clave = Ecto.UUID.generate()
attrs = %{"tipo" => "robo", "lat" => -16.3963, "lng" => -71.5340}
{:ok, :created, primero} = Incidents.create_incident(attrs, clave)
{:ok, :existing, repetido} = Incidents.create_incident(attrs, clave)
IO.puts("  - Mismo envío dos veces   -> mismo id: #{primero.id == repetido.id} (no se duplica)")
Repo.delete!(primero)
