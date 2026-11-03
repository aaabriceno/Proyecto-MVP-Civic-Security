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
    if (response == null) return const ApiFailure.network();

    final data = response.data;
    if (data is Map && data['error'] is Map) {
      final error = data['error'] as Map;
      return ApiFailure(
        code: error['code'] is String ? error['code'] as String : 'unknown',
        message: error['message'] is String
            ? error['message'] as String
            : 'El servidor rechazó la solicitud',
        fields: _parseFields(error['fields']),
      );
    }

    // Otra forma de error (por ejemplo un 413 o un 502 de un proxy)
    final status = response.statusCode ?? 0;
    return ApiFailure(
      code: 'http_$status',
      message: 'El servidor respondió con un error ($status)',
    );
  }

  final String code;
  final String message;

  /// Errores por campo de los 422, p. ej. `{"ubicacion": ["..."]}`.
  final Map<String, List<String>> fields;

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
