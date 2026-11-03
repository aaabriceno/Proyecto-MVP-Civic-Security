import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Cómo se descargan las teselas del mapa. Es un provider para que los tests
/// puedan reemplazarlo y no salir a internet.
final tileProviderProvider = Provider<TileProvider>(
  (ref) => NetworkTileProvider(),
);
