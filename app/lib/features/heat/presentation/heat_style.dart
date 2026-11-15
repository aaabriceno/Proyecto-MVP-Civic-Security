import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../incident/domain/incident.dart';
import '../domain/heat_map.dart';

// Del frame 05b: amarillo (baja) -> naranja -> rojo (alta)
const _amarillo = Color(0xFFFACC15);
const _naranja = Color(0xFFF97316);
const _rojo = Color(0xFFDC2626);

/// El círculo exterior de una celda mide este múltiplo de su lado: un poco más
/// de lo que ocupa, para que las celdas vecinas se fundan entre sí.
const heatOuterFactor = 0.9;

const _metrosPorGrado = 111320.0;

/// Color de una celda según su intensidad (0 = baja, 1 = alta).
Color heatColor(double t) {
  final x = t.clamp(0.0, 1.0);
  return x < 0.5
      ? Color.lerp(_amarillo, _naranja, x / 0.5)!
      : Color.lerp(_naranja, _rojo, (x - 0.5) / 0.5)!;
}

/// Tres círculos concéntricos por celda, cada uno más chico y más opaco hacia el
/// centro, como en el diseño. El radio va en metros: crece y se encoge con el
/// zoom igual que el mapa.
///
/// Las menos activas se dibujan primero para que las más activas queden encima.
/// La [selected] lleva un borde.
List<CircleMarker> heatCircles(HeatMap data, {HeatCell? selected}) {
  final lado = data.cellDeg * _metrosPorGrado;
  const capas = [(heatOuterFactor, 0.18), (0.55, 0.30), (0.25, 0.55)];

  return [
    for (final cell in data.cells.reversed)
      for (final (i, (factor, alpha)) in capas.indexed)
        CircleMarker(
          point: cell.position,
          radius: lado * factor,
          useRadiusInMeter: true,
          color: heatColor(
            HeatMap.intensity(count: cell.count, max: data.max),
          ).withValues(alpha: alpha),
          borderColor: const Color(0xFF111827),
          borderStrokeWidth: identical(cell, selected) && i == 0 ? 2 : 0,
        ),
  ];
}

/// El título del cuadro de una zona. No exagera: "alta actividad" es de 5
/// reportes en adelante; con menos se dice lo que hay.
String zoneTitle(int count) => switch (count) {
  1 => 'Reporte en esta zona',
  < 5 => 'Zona con actividad',
  _ => 'Zona de alta actividad',
};

/// "7 reportes en 24 h · 5 robos, 2 peleas".
String zoneSummary(HeatCell cell, HeatWindow window) {
  final reportes = '${cell.count} ${cell.count == 1 ? 'reporte' : 'reportes'}';
  final cuando = switch (window) {
    HeatWindow.hour => 'la última hora',
    HeatWindow.day => '24 h',
    HeatWindow.week => '7 días',
  };

  // Del tipo más frecuente al menos; si empatan, en el orden de los tipos
  final tipos = cell.tipos.entries.toList()
    ..sort((a, b) {
      final porCantidad = b.value.compareTo(a.value);
      return porCantidad != 0
          ? porCantidad
          : a.key.index.compareTo(b.key.index);
    });
  final detalle = tipos.map((e) => _contar(e.key, e.value)).join(', ');

  return detalle.isEmpty
      ? '$reportes en $cuando'
      : '$reportes en $cuando · $detalle';
}

String _contar(IncidentType tipo, int n) {
  final (singular, plural) = switch (tipo) {
    IncidentType.robo => ('robo', 'robos'),
    IncidentType.agresionMujer => ('agresión a mujer', 'agresiones a mujeres'),
    IncidentType.maltratoAnimal => ('maltrato animal', 'maltratos animales'),
    IncidentType.peleaColegio => ('pelea', 'peleas'),
    IncidentType.actividadSospechosa => (
      'actividad sospechosa',
      'actividades sospechosas',
    ),
    IncidentType.otro => ('otro', 'otros'),
  };
  return '$n ${n == 1 ? singular : plural}';
}
