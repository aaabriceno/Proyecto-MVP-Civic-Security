import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// UCSP (sede San Lázaro). Solo es el centro de respaldo del mapa cuando no
/// hay ubicación del usuario, y el punto de pruebas del equipo.
const ucspCenter = LatLng(-16.3963, -71.5340);

/// Área de operación de Civic Security (Arequipa metropolitana).
/// Debe coincidir con el rectángulo que valida el backend.
final arequipaBounds = LatLngBounds(
  const LatLng(-16.60, -71.75),
  const LatLng(-16.25, -71.40),
);
