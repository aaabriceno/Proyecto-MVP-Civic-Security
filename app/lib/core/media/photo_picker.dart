import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

/// De dónde sale la foto.
enum PhotoSource { camera, gallery }

/// No se pudo abrir la cámara o la galería (sin permiso, sin cámara, etc.).
class PhotoPickerException implements Exception {
  const PhotoPickerException(this.source);

  final PhotoSource source;

  @override
  String toString() => 'PhotoPickerException($source)';
}

/// Pide una foto a la cámara o a la galería. Es una interfaz para poder
/// reemplazarla por una falsa en los tests.
abstract interface class PhotoPicker {
  /// Los bytes de la foto elegida, o `null` si la persona canceló. Lanza
  /// [PhotoPickerException] si no se pudo abrir.
  Future<Uint8List?> pick(PhotoSource source);
}

/// Usa `image_picker`. En Android abre la **cámara del sistema** (la app no pide
/// el permiso CAMERA ni lee tus fotos) o el **selector de fotos del sistema**: la
/// app solo recibe la imagen que la persona elige, no puede recorrer la galería.
class ImagePickerPhotoPicker implements PhotoPicker {
  ImagePickerPhotoPicker([ImagePicker? picker])
    : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  // Un tope de lado para que el teléfono no cargue 12 MP completos en memoria; el
  // tamaño final (1280 px) y la limpieza de metadatos los hace preparePhoto.
  static const _maxSide = 2560.0;

  @override
  Future<Uint8List?> pick(PhotoSource source) async {
    try {
      final file = await _picker.pickImage(
        source: source == PhotoSource.camera
            ? ImageSource.camera
            : ImageSource.gallery,
        maxWidth: _maxSide,
        maxHeight: _maxSide,
        // No hace falta leer los metadatos: de todos modos se descartan
        requestFullMetadata: false,
      );
      return file == null ? null : await file.readAsBytes();
    } on PlatformException {
      throw PhotoPickerException(source);
    }
  }
}

final photoPickerProvider = Provider<PhotoPicker>(
  (ref) => ImagePickerPhotoPicker(),
);
