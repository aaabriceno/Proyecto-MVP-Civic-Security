import 'package:latlong2/latlong.dart';

import '../../incident/domain/incident.dart';

/// Qué tan atrás cuenta el mapa de calor. [wire] es el valor que usa la API.
enum HeatWindow {
  hour('1h', 'Última hora'),
  day('24h', '24 h'),
  week('7d', '7 días');

  const HeatWindow(this.wire, this.label);

  final String wire;
  final String label;
}

/// Una celda de la cuadrícula: cuántos incidentes cayeron en ella.
class HeatCell {
  const HeatCell({
    required this.position,
    required this.count,
    required this.tipos,
    required this.franjaDesde,
    required this.franjaHasta,
  });

  /// El centro de la celda.
  final LatLng position;
  final int count;

  /// Cuántos incidentes hay de cada tipo.
  final Map<IncidentType, int> tipos;

  /// La franja de 3 horas (hora de Perú) en que más se reporta: de [franjaDesde]
  /// a [franjaHasta], en horas enteras.
  final int franjaDesde;
  final int franjaHasta;

  /// "18:00 – 21:00".
  String get franjaLabel => '${_hora(franjaDesde)} – ${_hora(franjaHasta)}';

  static String _hora(int h) => '${h.toString().padLeft(2, '0')}:00';
}

/// La respuesta de `GET /v1/map/heat`.
class HeatMap {
  const HeatMap({
    required this.cellDeg,
    required this.max,
    required this.cells,
  });

  /// Convierte el JSON de la API. Lanza [FormatException] si está malformado.
  /// Un tipo de incidente que esta versión no conoce se ignora (un servidor más
  /// nuevo que la app), igual que en el mapa de pines.
  factory HeatMap.fromJson(Object? json) {
    try {
      final data = json as Map<String, dynamic>;
      final cells = data['celdas'] as List<Object?>;
      return HeatMap(
        cellDeg: (data['cell_deg'] as num).toDouble(),
        max: (data['max'] as num).toInt(),
        cells: [for (final c in cells) _cell(c as Map<String, dynamic>)],
      );
    } on TypeError catch (e) {
      throw FormatException('Mapa de calor malformado: $e');
    }
  }

  static HeatCell _cell(Map<String, dynamic> json) {
    final franja = json['franja'] as Map<String, dynamic>;
    final tipos = <IncidentType, int>{};
    for (final entry in (json['tipos'] as Map<String, dynamic>).entries) {
      final tipo = IncidentType.fromWire(entry.key);
      if (tipo != null) tipos[tipo] = (entry.value as num).toInt();
    }
    return HeatCell(
      // La API manda lat y lng por separado, y LatLng pide lat primero
      position: LatLng(
        (json['lat'] as num).toDouble(),
        (json['lng'] as num).toDouble(),
      ),
      count: (json['count'] as num).toInt(),
      tipos: tipos,
      franjaDesde: (franja['desde'] as num).toInt(),
      franjaHasta: (franja['hasta'] as num).toInt(),
    );
  }

  /// Lado de cada celda, en grados.
  final double cellDeg;

  /// Los incidentes de la celda más activa.
  final int max;
  final List<HeatCell> cells;

  /// Qué tan caliente es una celda, de 0 a 1, respecto de la más activa. Con un
  /// piso de 4: si solo hay un reporte en toda la zona no se pinta como la
  /// "intensidad máxima", porque no lo es.
  static double intensity({required int count, required int max}) {
    final techo = max < 4 ? 4 : max;
    return (count / techo).clamp(0.0, 1.0);
  }
}
