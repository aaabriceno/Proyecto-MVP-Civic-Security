import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';

import 'tile_health.dart';

/// Las capas de mosaicos de OpenStreetMap, con el aviso de "mapa incompleto".
///
/// Cada pantalla con mapa crea uno en su `State`, usa [layer] en lugar de un
/// `TileLayer` suelto, pone [banner] donde quiera el aviso y lo cierra con
/// [dispose].
class MapTiles {
  MapTiles() {
    _resetStream = _reset.stream;
  }

  /// Fallas recientes; también la usan los tests.
  final health = TileHealth();

  final _reset = StreamController<void>.broadcast();
  late final Stream<void> _resetStream;
  bool _disposed = false;

  /// El mapa de fondo. Cada mosaico que no se descarga se anota en [health].
  TileLayer layer(TileProvider provider) => TileLayer(
    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    userAgentPackageName: 'pe.civicsecurity.civic_security',
    tileProvider: provider,
    errorTileCallback: (_, _, _) => health.report(),
    reset: _resetStream,
  );

  /// El aviso, para ponerlo encima del mapa.
  Widget banner() => TileErrorBanner(health: health, onRetry: retry);

  /// Olvida las fallas y vuelve a pedir los mosaicos que se ven. Si siguen
  /// fallando, el aviso vuelve a aparecer solo.
  void retry() {
    if (_disposed) return;
    health.clear();
    _reset.add(null);
  }

  void dispose() {
    _disposed = true;
    health.dispose();
    unawaited(_reset.close());
  }
}
