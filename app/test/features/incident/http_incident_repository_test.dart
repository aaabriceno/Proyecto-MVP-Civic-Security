import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:civic_security/core/network/api_failure.dart';
import 'package:civic_security/features/incident/data/incident_repository.dart';
import 'package:civic_security/features/incident/domain/incident.dart';
import 'package:civic_security/features/report/domain/new_incident.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Simula el servidor: devuelve una respuesta fija y guarda la petición.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.status, this.body, {this.error});

  final int status;
  final Object body;
  final DioException? error;
  RequestOptions? last;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    last = options;
    if (error != null) throw error!;
    return ResponseBody.fromString(
      body is String ? body as String : jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json; charset=utf-8'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

const _bbox = Bbox(
  minLng: -71.75,
  minLat: -16.6,
  maxLng: -71.4,
  maxLat: -16.25,
);

Map<String, dynamic> _incident(String id, {String tipo = 'robo'}) => {
  'id': id,
  'tipo': tipo,
  'descripcion': null,
  'lat': -16.4,
  'lng': -71.5,
  'estado': 'verificado',
  'creado_en': '2026-11-03T21:50:33Z',
};

HttpIncidentRepository _repo(_FakeAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'http://test'))
    ..httpClientAdapter = adapter;
  return HttpIncidentRepository(dio);
}

void main() {
  test('pide /v1/map/snapshot con el bbox y devuelve los incidentes', () async {
    final adapter = _FakeAdapter(200, {
      'data': {
        'incidentes': [_incident('a'), _incident('b', tipo: 'pelea_colegio')],
      },
    });
    final result = await _repo(adapter).fetchSnapshot(_bbox);

    expect(adapter.last!.path, '/v1/map/snapshot');
    expect(adapter.last!.method, 'GET');
    expect(adapter.last!.queryParameters['bbox'], _bbox.toQuery());
    expect(result.map((i) => i.id), ['a', 'b']);
    expect(result[1].tipo, IncidentType.peleaColegio);
  });

  test('omite los tipos que esta versión de la app no conoce', () async {
    final adapter = _FakeAdapter(200, {
      'data': {
        'incidentes': [_incident('a'), _incident('b', tipo: 'ovni')],
      },
    });
    expect((await _repo(adapter).fetchSnapshot(_bbox)).map((i) => i.id), ['a']);
  });

  test('lista vacía', () async {
    final adapter = _FakeAdapter(200, {
      'data': {'incidentes': []},
    });
    expect(await _repo(adapter).fetchSnapshot(_bbox), isEmpty);
  });

  test('error de la API -> ApiFailure con su código', () async {
    final adapter = _FakeAdapter(400, {
      'error': {'code': 'invalid_bbox', 'message': 'bbox inválido'},
    });
    await expectLater(
      _repo(adapter).fetchSnapshot(_bbox),
      throwsA(isA<ApiFailure>().having((f) => f.code, 'code', 'invalid_bbox')),
    );
  });

  test('sin conexión -> ApiFailure network', () async {
    final adapter = _FakeAdapter(
      200,
      const {},
      error: DioException(
        requestOptions: RequestOptions(path: '/x'),
        type: DioExceptionType.connectionError,
      ),
    );
    await expectLater(
      _repo(adapter).fetchSnapshot(_bbox),
      throwsA(isA<ApiFailure>().having((f) => f.code, 'code', 'network')),
    );
  });

  test(
    'una respuesta con otra forma -> ApiFailure invalid_response, sin crash',
    () async {
      for (final body in <Object>[
        {'data': 'nada'},
        {'otra': 'cosa'},
        '[1,2,3]',
        {
          'data': {
            'incidentes': [
              // tipo y estado válidos pero sin coordenadas: JSON malformado
              {
                'id': 'x',
                'tipo': 'robo',
                'estado': 'verificado',
                'creado_en': '2026-11-03T21:50:33Z',
              },
            ],
          },
        },
      ]) {
        await expectLater(
          _repo(_FakeAdapter(200, body)).fetchSnapshot(_bbox),
          throwsA(
            isA<ApiFailure>().having((f) => f.code, 'code', 'invalid_response'),
          ),
          reason: 'cuerpo: $body',
        );
      }
    },
  );

  group('create', () {
    const input = NewIncident(
      tipo: IncidentType.robo,
      descripcion: 'Me robaron',
      lat: -16.4,
      lng: -71.5,
    );
    const key = '0b1b6b0e-4f6e-4a0e-9d44-9a5d0e0f7a11';

    test('hace POST /v1/incidents con la clave y el cuerpo', () async {
      final adapter = _FakeAdapter(201, {'data': _incident('nuevo')});
      final created = await _repo(adapter).create(input, idempotencyKey: key);

      expect(adapter.last!.method, 'POST');
      expect(adapter.last!.path, '/v1/incidents');
      expect(adapter.last!.headers['idempotency-key'], key);
      expect(adapter.last!.data, input.toJson());
      expect(created.id, 'nuevo');
    });

    test(
      'un 200 (reintento ya guardado) también devuelve el incidente',
      () async {
        final adapter = _FakeAdapter(200, {'data': _incident('existente')});
        expect(
          (await _repo(adapter).create(input, idempotencyKey: key)).id,
          'existente',
        );
      },
    );

    test('422 -> ApiFailure con los errores por campo', () async {
      final adapter = _FakeAdapter(422, {
        'error': {
          'code': 'validation_failed',
          'message': 'Datos inválidos',
          'fields': {
            'descripcion': ['no escribas datos personales'],
          },
        },
      });
      await expectLater(
        _repo(adapter).create(input, idempotencyKey: key),
        throwsA(
          isA<ApiFailure>()
              .having((f) => f.code, 'code', 'validation_failed')
              .having((f) => f.fields['descripcion'], 'fields', [
                'no escribas datos personales',
              ]),
        ),
      );
    });

    test('una respuesta sin incidente -> invalid_response', () async {
      for (final body in <Object>[
        {'data': 'x'},
        {'otra': 1},
        {'data': _incident('x', tipo: 'ovni')},
      ]) {
        await expectLater(
          _repo(_FakeAdapter(201, body)).create(input, idempotencyKey: key),
          throwsA(
            isA<ApiFailure>().having((f) => f.code, 'code', 'invalid_response'),
          ),
          reason: '$body',
        );
      }
    });

    test('sin conexión -> network', () async {
      final adapter = _FakeAdapter(
        201,
        const {},
        error: DioException(
          requestOptions: RequestOptions(path: '/x'),
          type: DioExceptionType.connectionTimeout,
        ),
      );
      await expectLater(
        _repo(adapter).create(input, idempotencyKey: key),
        throwsA(isA<ApiFailure>().having((f) => f.code, 'code', 'network')),
      );
    });
  });
}
