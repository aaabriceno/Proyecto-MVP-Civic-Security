import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';

/// Un servidor de mosaicos caído: cada mosaico que se pide falla, como pasa con
/// un 503 o sin internet. Con [failing] en `false` vuelve a responder bien.
class FailingTileProvider extends TileProvider {
  // PNG transparente de 1x1 píxel
  static final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
  );

  bool failing = true;

  /// Cuántos mosaicos se han pedido en total.
  int requests = 0;

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    requests++;
    return failing ? _FailingImage() : MemoryImage(_png);
  }
}

class _FailingImage extends ImageProvider<_FailingImage> {
  @override
  Future<_FailingImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    _FailingImage key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(
    Future<ImageInfo>.error(Exception('HTTP request failed, statusCode: 503')),
  );
}
