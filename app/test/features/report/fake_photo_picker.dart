import 'dart:async';
import 'dart:typed_data';

import 'package:civic_security/core/media/photo_picker.dart';

/// Selector de fotos falso: devuelve lo que el test deje en [result] y anota de
/// qué fuente se pidió.
class FakePhotoPicker implements PhotoPicker {
  /// La foto "tomada". `null` = la persona canceló.
  Uint8List? result;

  /// Si no es null, el siguiente `pick` falla con esto.
  Object? error;

  /// Si no es null, `pick` espera a que este completer termine.
  Completer<void>? gate;

  final requested = <PhotoSource>[];

  @override
  Future<Uint8List?> pick(PhotoSource source) async {
    requested.add(source);
    if (gate != null) await gate!.future;
    if (error != null) throw error!;
    return result;
  }
}
