import 'dart:convert';

import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';

/// Teselas transparentes: los tests no deben salir a internet.
class BlankTileProvider extends TileProvider {
  // PNG transparente de 1x1 píxel
  static final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
  );

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      MemoryImage(_png);
}
