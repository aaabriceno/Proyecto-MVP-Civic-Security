import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;

/// Lado más largo de la foto que se sube, en píxeles. Basta para ver qué pasó y
/// mantiene el archivo en ~150 KB.
const maxPhotoSide = 1280;

/// Una foto de partida más grande que esto ni se intenta abrir (una de cámara
/// pesa unos 5 MB; decodificar algo mucho mayor agotaría la memoria).
const maxPhotoInputBytes = 30 * 1024 * 1024;

/// El archivo no es una imagen que se pueda abrir (formato no compatible o
/// dañada).
class UnreadablePhotoException implements Exception {
  const UnreadablePhotoException();

  @override
  String toString() => 'UnreadablePhotoException';
}

/// El archivo de partida es demasiado grande.
class PhotoTooLargeException implements Exception {
  const PhotoTooLargeException();

  @override
  String toString() => 'PhotoTooLargeException';
}

/// Prepara una foto para subirla: la convierte en un JPEG **nuevo**, sin nada de
/// lo que traía escondido.
///
/// Una foto de celular lleva el GPS de quien la tomó, el modelo, el número de
/// serie y la fecha; a veces comentarios, un perfil de color o datos de edición.
/// En lugar de borrar esas etiquetas una por una (siempre se escapa alguna), se
/// **dibuja la imagen en un lienzo en blanco** y se vuelve a codificar: lo único
/// que pasa son los píxeles. La rotación guardada en los metadatos se aplica al
/// decodificar (si no, la foto quedaría de lado). El servidor vuelve a revisar el
/// resultado y rechaza lo que traiga cualquier metadato.
///
/// No detecta ni difumina rostros ni placas: eso está en los píxeles.
///
/// Lanza [UnreadablePhotoException] o [PhotoTooLargeException]. Es pesada (decodifica
/// y codifica la imagen completa): usa [preparePhoto] para no congelar la pantalla.
Uint8List preparePhotoSync(Uint8List original) {
  if (original.length > maxPhotoInputBytes) {
    throw const PhotoTooLargeException();
  }

  // El decodificador ya aplica la rotación guardada en los metadatos (una foto de
  // celular suele venir "de lado" con una etiqueta que dice cómo girarla), así que
  // aquí ya está derecha; los tests de rotación lo vigilan.
  final upright = _decode(original);

  // Solo se reduce: una foto chica no se agranda
  final longest = math.max(upright.width, upright.height);
  final scale = maxPhotoSide / longest;
  final sized = longest > maxPhotoSide
      ? img.copyResize(
          upright,
          width: (upright.width * scale).round(),
          height: (upright.height * scale).round(),
          interpolation: img.Interpolation.average,
        )
      : upright;

  // Lienzo nuevo: sin EXIF, sin perfil de color, sin comentarios. Fondo blanco
  // para que la transparencia de un PNG no se vuelva negra.
  final clean = img.Image(
    width: sized.width,
    height: sized.height,
    numChannels: 3,
  )..clear(img.ColorRgb8(255, 255, 255));
  img.compositeImage(clean, sized);

  return Uint8List.fromList(img.encodeJpg(clean, quality: 80));
}

img.Image _decode(Uint8List bytes) {
  try {
    final image = img.decodeImage(bytes);
    if (image != null) return image;
  } on Object {
    // Una imagen dañada puede fallar de muchas formas dentro del decodificador
  }
  throw const UnreadablePhotoException();
}

/// Como [preparePhotoSync], pero en otro hilo para no congelar la pantalla.
Future<Uint8List> preparePhoto(Uint8List original) =>
    compute(preparePhotoSync, original);

/// Cómo se prepara una foto. Es un provider para que los tests de pantallas lo
/// reemplacen (un hilo aparte no funciona dentro de `testWidgets`).
typedef PhotoPreparer = Future<Uint8List> Function(Uint8List original);

final photoPreparerProvider = Provider<PhotoPreparer>((ref) => preparePhoto);
