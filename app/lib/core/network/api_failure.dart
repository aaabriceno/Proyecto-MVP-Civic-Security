import 'package:dio/dio.dart';

/// Error de la API ya traducido a algo que la interfaz puede mostrar.
///
/// El servidor responde siempre con
/// `{"error": {"code": "...", "message": "...", "fields": {...}}}`.
class ApiFailure implements Exception {
  const ApiFailure({
    required this.code,
    required this.message,
    this.fields = const {},
    this.retryAfter,
  });

  /// Sin conexión, tiempo agotado o servidor caído.
  const ApiFailure.network()
    : this(code: 'network', message: 'No se pudo conectar con el servidor');

  const ApiFailure.invalidResponse()
    : this(
        code: 'invalid_response',
        message: 'El servidor respondió algo inesperado',
      );

  const ApiFailure.unexpected()
    : this(code: 'unexpected', message: 'Ocurrió un error inesperado');

  factory ApiFailure.fromDio(DioException e) {
    final response = e.response;
    if (response == null) {
      // Dio envuelve el error de leer un cuerpo que no es JSON en un
      // DioException sin respuesta: el servidor sí contestó, no es falta de red
      return e.error is FormatException
          ? const ApiFailure.invalidResponse()
          : const ApiFailure.network();
    }

    final retryAfter = _parseRetryAfter(response.headers.value('retry-after'));

    final data = response.data;
    if (data is Map && data['error'] is Map) {
      final error = data['error'] as Map;
      return ApiFailure(
        code: error['code'] is String ? error['code'] as String : 'unknown',
        message: error['message'] is String
            ? error['message'] as String
            : 'El servidor rechazó la solicitud',
        fields: _parseFields(error['fields']),
        retryAfter: retryAfter,
      );
    }

    // Otra forma de error (por ejemplo un 413 o un 502 de un proxy)
    final status = response.statusCode ?? 0;
    return ApiFailure(
      code: 'http_$status',
      message: 'El servidor respondió con un error ($status)',
      retryAfter: retryAfter,
    );
  }

  final String code;
  final String message;

  /// Errores por campo de los 422, p. ej. `{"ubicacion": ["..."]}`.
  final Map<String, List<String>> fields;

  /// Cuánto esperar antes de reintentar, si el servidor lo indicó con la
  /// cabecera `retry-after` (un 429 o un 503). Sirve para la cuenta regresiva
  /// de una cuenta bloqueada.
  final Duration? retryAfter;

  /// Solo acepta segundos enteros positivos; cualquier otra cosa es `null`.
  static Duration? _parseRetryAfter(String? raw) {
    final seconds = int.tryParse(raw?.trim() ?? '');
    return seconds != null && seconds > 0 ? Duration(seconds: seconds) : null;
  }

  static Map<String, List<String>> _parseFields(Object? raw) {
    if (raw is! Map) return const {};
    return {
      for (final entry in raw.entries)
        if (entry.key is String && entry.value is List)
          entry.key as String: [
            for (final v in entry.value as List) v.toString(),
          ],
    };
  }

  @override
  String toString() => 'ApiFailure($code: $message)';
}
