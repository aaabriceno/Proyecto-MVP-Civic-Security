# Genera un mapa HTML con los incidentes de la base de datos (demo del avance 1).
#
#     mix run priv/repo/demo_mapa.exs
#
# Escribe Avances-MVP/avance-1/mapa-demo.html. Necesita internet para cargar
# Leaflet y los mapas de OpenStreetMap. Los scripts llevan hash de integridad
# (SRI): si el CDN sirviera un archivo distinto, el navegador lo rechaza.

alias Civic.Repo
alias Civic.Incidents.Incident

Logger.configure(level: :info)

incidentes =
  Incident
  |> Repo.all()
  |> Enum.map(fn i ->
    {lat, lng} = Incident.coords(i)

    %{
      tipo: i.tipo,
      estado: i.estado,
      descripcion: i.descripcion,
      lat: lat,
      lng: lng,
      # Hora de Lima (UTC-5)
      hora: i.inserted_at |> DateTime.add(-5, :hour) |> Calendar.strftime("%d/%m %H:%M")
    }
  end)

datos = Jason.encode!(incidentes, escape: :html_safe)

html = """
<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Civic Security - Mapa de incidentes (datos ficticios)</title>
<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css"
      integrity="sha384-sHL9NAb7lN7rfvG5lfHpm643Xkcjzp4jFvuavGOndn6pjVqS6ny56CAt3nsEVT4H" crossorigin="anonymous">
<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"
        integrity="sha384-cxOPjt7s7Iz04uaHJceBmS+qpjv2JkIHNVcuOrM+YHwZOmJGBXI00mdUXEq65HTH" crossorigin="anonymous"></script>
<script src="https://unpkg.com/leaflet.heat@0.2.0/dist/leaflet-heat.js"
        integrity="sha384-mFKkGiGvT5vo1fEyGCD3hshDdKmW3wzXW/x+fWriYJArD0R3gawT6lMvLboM22c0" crossorigin="anonymous"></script>
<style>
  html, body, #mapa { height: 100%; margin: 0; font-family: sans-serif; }
  .panel { background: white; padding: 8px 12px; border-radius: 6px;
           box-shadow: 0 1px 4px rgba(0,0,0,.3); font-size: 14px; line-height: 1.5; }
  .punto { display: inline-block; width: 12px; height: 12px; border-radius: 50%; margin-right: 6px; }
</style>
</head>
<body>
<div id="mapa"></div>
<script>
  const INCIDENTES = #{datos};
  const COLORES = { verificado: "#2e7d32", sin_verificar: "#f57c00", descartado: "#9e9e9e" };
  const ETIQUETAS = {
    robo: "Robo", agresion_mujer: "Agresión a mujer", maltrato_animal: "Maltrato animal",
    pelea_colegio: "Pelea en salida de colegio", actividad_sospechosa: "Actividad sospechosa",
    otro: "Otro"
  };
  const ESTADOS = { verificado: "Verificado", sin_verificar: "Sin verificar", descartado: "Descartado" };

  function escapar(texto) {
    const div = document.createElement("div");
    div.textContent = texto ?? "";
    return div.innerHTML;
  }

  const mapa = L.map("mapa").setView([-16.3897524, -71.5356732], 14);
  // OSM bloquea las páginas abiertas como archivo (file://) porque no envían
  // Referer: abrir el mapa desde un servidor local (ver guion-demo.md).
  L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
    maxZoom: 19, attribution: "&copy; OpenStreetMap contributors"
  }).addTo(mapa);

  const pines = L.layerGroup(INCIDENTES.map(i =>
    L.circleMarker([i.lat, i.lng], {
      radius: 8, color: "#fff", weight: 2, fillColor: COLORES[i.estado], fillOpacity: 0.9
    }).bindPopup(
      "<b>" + escapar(ETIQUETAS[i.tipo]) + "</b><br>" +
      escapar(ESTADOS[i.estado]) + " · " + escapar(i.hora) + "<br>" +
      escapar(i.descripcion)
    )
  )).addTo(mapa);

  const calor = L.heatLayer(
    INCIDENTES.filter(i => i.estado !== "descartado").map(i => [i.lat, i.lng, 1]),
    { radius: 30, blur: 25, maxZoom: 15 }
  );

  const ucsp = L.circle([-16.3963, -71.5340], {
    radius: 1000, color: "#1565c0", fill: false, dashArray: "6 6"
  }).bindTooltip("1 km alrededor de la UCSP (radio de votación)");
  ucsp.addTo(mapa);

  L.control.layers(null, {
    "Pines por estado": pines,
    "Mapa de calor": calor,
    "Radio de 1 km (UCSP)": ucsp
  }, { collapsed: false }).addTo(mapa);

  const leyenda = L.control({ position: "bottomleft" });
  leyenda.onAdd = () => {
    const div = L.DomUtil.create("div", "panel");
    div.innerHTML =
      "<b>Civic Security</b> · " + INCIDENTES.length + " reportes (datos ficticios)<br>" +
      Object.keys(COLORES).map(e =>
        '<span class="punto" style="background:' + COLORES[e] + '"></span>' + ESTADOS[e]
      ).join("<br>");
    return div;
  };
  leyenda.addTo(mapa);
</script>
</body>
</html>
"""

destino = Path.expand("../Avances-MVP/avance-1/mapa-demo.html", File.cwd!())
File.write!(destino, html)
IO.puts("Mapa generado con #{length(incidentes)} incidentes: #{destino}")
