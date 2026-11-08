import 'package:latlong2/latlong.dart';

/// Los tipos de incidente. [wire] es el valor que usa la API.
enum IncidentType {
  robo('robo', 'Robo'),
  agresionMujer('agresion_mujer', 'Agresión a mujer'),
  maltratoAnimal('maltrato_animal', 'Maltrato animal'),
  peleaColegio('pelea_colegio', 'Pelea en salida de colegio'),
  actividadSospechosa('actividad_sospechosa', 'Actividad sospechosa'),
  otro('otro', 'Otro');

  const IncidentType(this.wire, this.label);

  final String wire;
  final String label;

  /// `null` si el servidor envía un tipo que esta versión no conoce.
  static IncidentType? fromWire(String? value) {
    for (final t in values) {
      if (t.wire == value) return t;
    }
    return null;
  }
}

/// Resultado de la validación comunitaria.
enum IncidentStatus {
  sinVerificar('sin_verificar', 'Sin verificar'),
  verificado('verificado', 'Verificado'),
  descartado('descartado', 'Descartado');

  const IncidentStatus(this.wire, this.label);

  final String wire;
  final String label;

  static IncidentStatus? fromWire(String? value) {
    for (final s in values) {
      if (s.wire == value) return s;
    }
    return null;
  }
}

class Incident {
  const Incident({
    required this.id,
    required this.tipo,
    required this.descripcion,
    required this.position,
    required this.estado,
    required this.creadoEn,
  });

  /// Convierte el JSON de la API. Devuelve `null` si el tipo o el estado no se
  /// conocen (un servidor más nuevo que la app): ese reporte simplemente no se
  /// muestra, en vez de romper todo el mapa. Lanza [FormatException] si el
  /// JSON está malformado.
  static Incident? tryFromJson(Map<String, dynamic> json) {
    try {
      final tipo = IncidentType.fromWire(json['tipo'] as String?);
      final estado = IncidentStatus.fromWire(json['estado'] as String?);
      if (tipo == null || estado == null) return null;

      return Incident(
        id: json['id'] as String,
        tipo: tipo,
        descripcion: json['descripcion'] as String?,
        // La API manda lat y lng por separado, y LatLng pide lat primero
        position: LatLng(
          (json['lat'] as num).toDouble(),
          (json['lng'] as num).toDouble(),
        ),
        estado: estado,
        creadoEn: DateTime.parse(json['creado_en'] as String).toUtc(),
      );
    } on TypeError catch (e) {
      throw FormatException('Incidente malformado: $e');
    }
  }

  final String id;
  final IncidentType tipo;
  final String? descripcion;
  final LatLng position;
  final IncidentStatus estado;

  /// Siempre en UTC; se convierte a hora local solo al mostrarla.
  final DateTime creadoEn;
}

/// Rectángulo geográfico que se pide a `GET /v1/map/snapshot`.
class Bbox {
  const Bbox({
    required this.minLng,
    required this.minLat,
    required this.maxLng,
    required this.maxLat,
  });

  /// Recorta a los rangos válidos de coordenadas.
  factory Bbox.fromCorners({
    required double south,
    required double west,
    required double north,
    required double east,
  }) => Bbox(
    minLng: west.clamp(-180.0, 180.0),
    minLat: south.clamp(-90.0, 90.0),
    maxLng: east.clamp(-180.0, 180.0),
    maxLat: north.clamp(-90.0, 90.0),
  );

  final double minLng;
  final double minLat;
  final double maxLng;
  final double maxLat;

  /// ¿El punto cae dentro del rectángulo? (el borde cuenta como dentro, igual
  /// que `ST_Intersects` en el servidor).
  bool contains(LatLng point) =>
      point.longitude >= minLng &&
      point.longitude <= maxLng &&
      point.latitude >= minLat &&
      point.latitude <= maxLat;

  /// `minLng,minLat,maxLng,maxLat` (longitud primero, como PostGIS), con 6
  /// decimales (~10 cm) y sin notación científica.
  String toQuery() =>
      '${minLng.toStringAsFixed(6)},${minLat.toStringAsFixed(6)},'
      '${maxLng.toStringAsFixed(6)},${maxLat.toStringAsFixed(6)}';

  @override
  bool operator ==(Object other) =>
      other is Bbox &&
      other.minLng == minLng &&
      other.minLat == minLat &&
      other.maxLng == maxLng &&
      other.maxLat == maxLat;

  @override
  int get hashCode => Object.hash(minLng, minLat, maxLng, maxLat);

  @override
  String toString() => 'Bbox(${toQuery()})';
}
