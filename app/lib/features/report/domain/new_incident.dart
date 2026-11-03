import '../../incident/domain/incident.dart';

/// Lo que se envía al crear un reporte. No lleva nada del usuario: el reporte
/// es anónimo.
class NewIncident {
  const NewIncident({
    required this.tipo,
    required this.lat,
    required this.lng,
    this.descripcion,
  });

  final IncidentType tipo;
  final double lat;
  final double lng;
  final String? descripcion;

  /// La descripción sin espacios sobrantes; `null` si queda vacía.
  String? get _cleanDescription {
    final text = descripcion?.trim();
    return (text == null || text.isEmpty) ? null : text;
  }

  Map<String, dynamic> toJson() => {
    'tipo': tipo.wire,
    'lat': lat,
    'lng': lng,
    if (_cleanDescription != null) 'descripcion': _cleanDescription,
  };

  // Dos reportes con el mismo contenido son el mismo reporte (se usa para
  // decidir si un reintento reutiliza la clave de idempotencia)
  @override
  bool operator ==(Object other) =>
      other is NewIncident &&
      other.tipo == tipo &&
      other.lat == lat &&
      other.lng == lng &&
      other._cleanDescription == _cleanDescription;

  @override
  int get hashCode => Object.hash(tipo, lat, lng, _cleanDescription);
}
