import '../../../core/network/api_failure.dart';

/// Qué decirle a la persona cuando entrar o registrarse falla.
///
/// Solo se usan mensajes propios, nunca el texto del servidor: los códigos que
/// conocemos tienen un mensaje pensado y los demás pueden traer detalles
/// internos que no deben mostrarse.
String authFailureMessage(ApiFailure failure) => switch (failure.code) {
  // El mismo mensaje para alias inexistente y contraseña mala: no se debe
  // poder averiguar qué alias existen
  'invalid_credentials' => 'Alias o contraseña incorrectos.',
  'account_locked' =>
    'Demasiados intentos fallidos. Por seguridad, espera un momento antes de '
        'volver a intentar.',
  'rate_limited' =>
    'Hay demasiados intentos desde esta conexión. Espera un momento y vuelve '
        'a intentar.',
  'server_busy' =>
    'El servidor está muy ocupado. Intenta de nuevo en unos segundos.',
  'network' => 'Sin conexión. Revisa tu internet e inténtalo de nuevo.',
  'validation_failed' => 'Revisa los datos e inténtalo de nuevo.',
  _ => 'No pudimos completar la acción. Inténtalo de nuevo en un momento.',
};

/// Cuánto hay que esperar antes de reintentar, para mostrar una cuenta
/// regresiva. Solo en los errores que de verdad piden esperar.
Duration? waitFor(ApiFailure failure) => switch (failure.code) {
  'account_locked' || 'rate_limited' || 'server_busy' => failure.retryAfter,
  _ => null,
};

/// El primer error del [field] (`alias`, `password`...) en un 422, o `null`.
String? fieldErrorOf(ApiFailure? failure, String field) {
  final messages = failure?.fields[field];
  return messages == null || messages.isEmpty ? null : messages.first;
}

/// La espera como `m:ss`: `0:45`, `1:05`. Redondea hacia arriba, porque con
/// 200 ms de espera todavía falta un segundo para poder reintentar.
String formatCountdown(Duration wait) {
  final seconds = wait.isNegative ? 0 : (wait.inMilliseconds / 1000).ceil();
  final minutes = seconds ~/ 60;
  final rest = (seconds % 60).toString().padLeft(2, '0');
  return '$minutes:$rest';
}
