import 'package:civic_security/core/network/api_failure.dart';
import 'package:civic_security/core/network/auth_interceptor.dart';
import 'package:civic_security/features/incident/data/incident_repository.dart';
import 'package:civic_security/features/incident/domain/incident.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import '../../core/fake_http_adapter.dart';

const _id = 'f92c3305-b156-4ceb-a7c1-9f101f3d0c7b';
const _aqui = LatLng(-16.4, -71.53);

Map<String, dynamic> _json({Object? confirmaciones, Object? falsos}) => {
  'id': _id,
  'tipo': 'robo',
  'descripcion': null,
  'lat': -16.4,
  'lng': -71.5,
  'estado': 'sin_verificar',
  'tiene_foto': false,
  'creado_en': '2026-11-03T21:50:33Z',
  'confirmaciones': ?confirmaciones,
  'falsos': ?falsos,
};

Map<String, dynamic> _errorBody(String code) => {
  'error': {'code': code, 'message': 'mensaje del servidor'},
};

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
  group('Incident: votos', () {
    test('lee las confirmaciones y los falsos', () {
      final incident = Incident.tryFromJson(
        _json(confirmaciones: 2, falsos: 1),
      )!;

      expect(incident.confirmaciones, 2);
      expect(incident.falsos, 1);
    });

    test('un servidor viejo que no los manda: cero', () {
      final incident = Incident.tryFromJson(_json())!;

      expect(incident.confirmaciones, 0);
      expect(incident.falsos, 0);
    });

    test('copyWith conserva los votos', () {
      final incident = Incident.tryFromJson(
        _json(confirmaciones: 2, falsos: 1),
      )!;

      final copy = incident.copyWith(tieneFoto: true);

      expect((copy.confirmaciones, copy.falsos), (2, 1));
    });

    test('VoteValue usa el texto que espera la API', () {
      expect(VoteValue.confirmo.wire, 'confirmo');
      expect(VoteValue.falso.wire, 'falso');
    });
  });

  group('vote', () {
    test('hace POST con el voto y la ubicación, con la sesión', () async {
      final adapter = FakeHttpAdapter(201, {'data': _json(confirmaciones: 1)});

      await _repo(
        adapter,
        token: 'access-1',
      ).vote(_id, VoteValue.confirmo, _aqui);

      expect(adapter.last!.method, 'POST');
      expect(adapter.last!.path, '/v1/incidents/$_id/votes');
      expect(adapter.last!.headers['authorization'], 'Bearer access-1');
      expect(adapter.last!.data, {
        'valor': 'confirmo',
        'lat': -16.4,
        'lng': -71.53,
      });
    });

    test('devuelve el reporte con los contadores nuevos', () async {
      final adapter = FakeHttpAdapter(201, {
        'data': _json(confirmaciones: 3)..['estado'] = 'verificado',
      });

      final incident = await _repo(
        adapter,
        token: 'a',
      ).vote(_id, VoteValue.confirmo, _aqui);

      expect(incident.id, _id);
      expect(incident.confirmaciones, 3);
      expect(incident.estado, IncidentStatus.verificado);
    });

    test('sin sesión no sale ninguna petición', () async {
      final adapter = FakeHttpAdapter(201, {'data': _json()});

      final failure = await _failureOf(
        () => _repo(adapter).vote(_id, VoteValue.falso, _aqui),
      );

      expect(failure.code, 'unauthorized');
      expect(adapter.calls, 0);
    });

    test('los errores del servidor llegan con su código', () async {
      const casos = {
        403: 'not_verified',
        409: 'already_voted',
        422: 'too_far',
        404: 'not_found',
      };

      for (final MapEntry(key: status, value: code) in casos.entries) {
        final adapter = FakeHttpAdapter(status, _errorBody(code));

        final failure = await _failureOf(
          () => _repo(adapter, token: 'a').vote(_id, VoteValue.falso, _aqui),
        );

        expect(failure.code, code, reason: 'HTTP $status');
      }
    });

    test('una respuesta que no es un reporte es invalid_response', () async {
      final adapter = FakeHttpAdapter(201, {'data': 'nada'});

      final failure = await _failureOf(
        () => _repo(adapter, token: 'a').vote(_id, VoteValue.falso, _aqui),
      );

      expect(failure.code, 'invalid_response');
    });

    test('sin conexión es network', () async {
      final adapter = FakeHttpAdapter(
        0,
        null,
        error: DioException(
          requestOptions: RequestOptions(path: '/'),
          type: DioExceptionType.connectionError,
        ),
      );

      final failure = await _failureOf(
        () => _repo(adapter, token: 'a').vote(_id, VoteValue.confirmo, _aqui),
      );

      expect(failure.code, 'network');
    });
  });
}
