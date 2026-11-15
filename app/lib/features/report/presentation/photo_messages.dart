import '../../../core/network/api_failure.dart';

/// Qué decirle a la persona cuando la foto de su reporte no se pudo subir. Solo
/// mensajes propios: nunca el texto del servidor.
String photoFailureMessage(ApiFailure failure) => switch (failure.code) {
  'network' => 'No pudimos subir la foto. Revisa tu conexión.',
  'photo_too_large' => 'La foto es demasiado pesada.',
  'photo_has_metadata' || 'invalid_photo' => 'No pudimos usar la foto.',
  'storage_unavailable' => 'No pudimos guardar la foto. Intenta de nuevo.',
  _ => 'No pudimos subir la foto.',
};

/// ¿Vale la pena reintentar? No si volvería a fallar igual (la foto misma es el
/// problema, o no es de quien la sube).
bool canRetryPhoto(ApiFailure failure) => !const {
  'photo_has_metadata',
  'invalid_photo',
  'photo_too_large',
  'not_author',
  'not_found',
  'unsupported_media_type',
}.contains(failure.code);
