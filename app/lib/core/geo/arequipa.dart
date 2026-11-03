import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Área de operación de Civic Security (Arequipa metropolitana).
/// Debe coincidir con el rectángulo que valida el backend.
///
/// Es la vista del mapa cuando no hay ubicación del usuario y el límite para
/// decidir si el usuario está dentro del área de servicio. No restringe el
/// mapa: las teselas cubren todo el mundo.
final arequipaBounds = LatLngBounds(
  const LatLng(-16.60, -71.75),
  const LatLng(-16.25, -71.40),
);
