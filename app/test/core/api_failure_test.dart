import 'package:civic_security/core/network/api_failure.dart';
import 'package:civic_security/core/network/api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

DioException _http(
  int status,
  Object? data, {
  Map<String, List<String>>? headers,
}) {
  final req = RequestOptions(path: '/x');
  return DioException(
    requestOptions: req,
    type: DioExceptionType.badResponse,
    response: Response(
      requestOptions: req,
      statusCode: status,
      data: data,
      headers: Headers.fromMap(headers ?? {}),
    ),
  );
}

void main() {
  group('ApiFailure.fromDio', () {
    test('sin conexión: código network y mensaje claro', () {
      final f = ApiFailure.fromDio(
        DioException(
          requestOptions: RequestOptions(path: '/x'),
          type: DioExceptionType.connectionError,
        ),
      );
      expect(f.code, 'network');
      expect(f.message, 'No se pudo conectar con el servidor');
    });

    test('tiempo agotado también es network', () {
      final f = ApiFailure.fromDio(
        DioException(
          requestOptions: RequestOptions(path: '/x'),
          type: DioExceptionType.receiveTimeout,
        ),
      );
      expect(f.code, 'network');
    });

    test('lee el formato de error de la API, incluidos los fields', () {
      final f = ApiFailure.fromDio(
        _http(422, {
          'error': {
            'code': 'validation_failed',
            'message': 'Datos inválidos',
            'fields': {
              'ubicacion': ['La ubicación debe estar dentro de Arequipa'],
            },
          },
        }),
      );
      expect(f.code, 'validation_failed');
      expect(f.message, 'Datos inválidos');
      expect(f.fields['ubicacion'], [
        'La ubicación debe estar dentro de Arequipa',
      ]);
    });

    test('429 usa el mensaje del servidor y conserva el código', () {
      final f = ApiFailure.fromDio(
        _http(429, {
          'error': {
            'code': 'rate_limited',
            'message': 'Demasiadas solicitudes. Intenta de nuevo en 30 s.',
          },
        }),
      );
      expect(f.code, 'rate_limited');
      expect(f.message, contains('30 s'));
    });

    test('una respuesta que no tiene el formato de la API no rompe nada', () {
      final f = ApiFailure.fromDio(
        _http(413, {
          'errors': {'detail': 'Payload Too Large'},
        }),
      );
      expect(f.code, 'http_413');
      expect(f.message, isNotEmpty);
    });

    test('una respuesta con cuerpo de texto tampoco', () {
      expect(
        ApiFailure.fromDio(_http(502, '<html>Bad gateway</html>')).code,
        'http_502',
      );
    });
  });

  group('validateApiUrl', () {
    test('en release exige https', () {
      expect(
        () => validateApiUrl('http://api.civic.pe', release: true),
        throwsStateError,
      );
      expect(
        () => validateApiUrl('https://api.civic.pe', release: true),
        returnsNormally,
      );
    });

    test('en desarrollo permite http', () {
      expect(
        () => validateApiUrl('http://10.0.2.2:4000', release: false),
        returnsNormally,
      );
    });
  });
}
