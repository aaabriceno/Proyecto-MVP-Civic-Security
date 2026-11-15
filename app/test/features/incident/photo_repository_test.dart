import 'dart:convert';
import 'dart:typed_data';

import 'package:civic_security/core/network/api_failure.dart';
import 'package:civic_security/core/network/auth_interceptor.dart';
import 'package:civic_security/features/incident/data/incident_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../core/fake_http_adapter.dart';

const _id = 'f92c3305-b156-4ceb-a7c1-9f101f3d0c7b';

final _foto = Uint8List.fromList([0xFF, 0xD8, 1, 2, 3, 0xFF, 0xD9]);

Map<String, dynamic> _incidentBody({bool tieneFoto = true}) => {
  'data': {
    'id': _id,
    'tipo': 'robo',
    'descripcion': null,
    'lat': -16.4,
    'lng': -71.5,
    'estado': 'sin_verificar',
    'tiene_foto': tieneFoto,
    'creado_en': '2026-11-03T21:50:33Z',
  },
};

Map<String, dynamic> _errorBody(String code) => {
  'error': {'code': code, 'message': 'mensaje del servidor'},
};

/// Con el interceptor de sesión real y un access token fijo, como el que arma
/// `sessionDioProvider`.
HttpIncidentRepository _repo(FakeHttpAdapter adapter, {String? token}) {
  final dio = fakeDio(adapter);
  dio.interceptors.add(
    AuthInterceptor(
      dio: dio,
      accessToken: () async => token,
      refresh: () async => null,
    ),
  );
  return HttpIncidentRepository(dio);
}

Future<ApiFailure> _failureOf(Future<Object?> Function() call) async {
  try {
    await call();
  } on ApiFailure catch (failure) {
    return failure;
  }
  fail('Debió lanzar un ApiFailure');
}

void main() {
  group('uploadPhoto', () {
    test(
      'hace PUT con la foto cruda, como image/jpeg y con la sesión',
      () async {
        final adapter = FakeHttpAdapter(201, _incidentBody());

        await _repo(adapter, token: 'access-1').uploadPhoto(_id, _foto);

        expect(adapter.last!.method, 'PUT');
        expect(adapter.last!.path, '/v1/incidents/$_id/photo');
        expect(adapter.last!.headers['authorization'], 'Bearer access-1');
        expect(
          adapter.last!.headers['content-type'].toString(),
          startsWith('image/jpeg'),
        );
        expect(adapter.last!.data, _foto, reason: 'bytes tal cual, sin JSON');
      },
    );

    test('devuelve el incidente ya con su foto', () async {
      final adapter = FakeHttpAdapter(201, _incidentBody());

      final incident = await _repo(adapter, token: 'a').uploadPhoto(_id, _foto);

      expect(incident.id, _id);
      expect(incident.tieneFoto, isTrue);
    });

    test('sin sesión no sale ninguna petición', () async {
      final adapter = FakeHttpAdapter(201, _incidentBody());

      final failure = await _failureOf(
        () => _repo(adapter).uploadPhoto(_id, _foto),
      );

      expect(failure.code, 'unauthorized');
      expect(adapter.calls, 0);
    });

    test('los errores del servidor llegan con su código', () async {
      const casos = {
        403: 'not_author',
        409: 'photo_exists',
        413: 'photo_too_large',
        422: 'photo_has_metadata',
        404: 'not_found',
      };

      for (final MapEntry(key: status, value: code) in casos.entries) {
        final adapter = FakeHttpAdapter(status, _errorBody(code));

        final failure = await _failureOf(
          () => _repo(adapter, token: 'a').uploadPhoto(_id, _foto),
        );

        expect(failure.code, code, reason: '$status');
      }
    });

    test('sin conexión -> network', () async {
      final adapter = FakeHttpAdapter(
        0,
        null,
        error: DioException(
          requestOptions: RequestOptions(path: '/'),
          type: DioExceptionType.connectionError,
        ),
      );

      final failure = await _failureOf(
        () => _repo(adapter, token: 'a').uploadPhoto(_id, _foto),
      );

      expect(failure.code, 'network');
    });

    test('una respuesta sin incidente -> invalid_response', () async {
      final adapter = FakeHttpAdapter(201, {'data': 'nada'});

      final failure = await _failureOf(
        () => _repo(adapter, token: 'a').uploadPhoto(_id, _foto),
      );

      expect(failure.code, 'invalid_response');
    });
  });

  group('fetchPhoto', () {
    test('hace GET, es público (sin sesión) y devuelve los bytes', () async {
      final adapter = FakeHttpAdapter(200, null, bytes: _foto);

      final bytes = await _repo(adapter, token: 'access-1').fetchPhoto(_id);

      expect(adapter.last!.method, 'GET');
      expect(adapter.last!.path, '/v1/incidents/$_id/photo');
      expect(adapter.last!.headers.containsKey('authorization'), isFalse);
      expect(adapter.last!.responseType, ResponseType.bytes);
      expect(bytes, _foto);
    });

    test('un 404 con el error en JSON se traduce a su código', () async {
      final adapter = FakeHttpAdapter(
        404,
        null,
        bytes: Uint8List.fromList(
          utf8.encode(jsonEncode(_errorBody('not_found'))),
        ),
        contentType: 'application/json; charset=utf-8',
      );

      final failure = await _failureOf(() => _repo(adapter).fetchPhoto(_id));

      expect(failure.code, 'not_found');
    });

    test('un error que no es JSON se resume por su estado', () async {
      final adapter = FakeHttpAdapter(
        502,
        null,
        bytes: Uint8List.fromList(utf8.encode('<html>Bad gateway</html>')),
        contentType: 'text/html',
      );

      final failure = await _failureOf(() => _repo(adapter).fetchPhoto(_id));

      expect(failure.code, 'http_502');
    });

    test('sin conexión -> network', () async {
      final adapter = FakeHttpAdapter(
        0,
        null,
        error: DioException(
          requestOptions: RequestOptions(path: '/'),
          type: DioExceptionType.connectionError,
        ),
      );

      final failure = await _failureOf(() => _repo(adapter).fetchPhoto(_id));

      expect(failure.code, 'network');
    });

    test('una respuesta vacía -> invalid_response', () async {
      final adapter = FakeHttpAdapter(200, null, bytes: Uint8List(0));

      final failure = await _failureOf(() => _repo(adapter).fetchPhoto(_id));

      expect(failure.code, 'invalid_response');
    });
  });
}
