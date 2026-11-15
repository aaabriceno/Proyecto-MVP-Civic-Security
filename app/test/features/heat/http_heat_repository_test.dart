import 'package:civic_security/core/network/api_failure.dart';
import 'package:civic_security/features/heat/data/heat_repository.dart';
import 'package:civic_security/features/heat/domain/heat_map.dart';
import 'package:civic_security/features/incident/domain/incident.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../core/fake_http_adapter.dart';

const _bbox = Bbox(
  minLng: -71.75,
  minLat: -16.6,
  maxLng: -71.4,
  maxLat: -16.25,
);

const _respuesta = {
  'data': {
    'ventana': '24h',
    'cell_deg': 0.02,
    'max': 3,
    'celdas': [
      {
        'lat': -16.4,
        'lng': -71.5,
        'count': 3,
        'tipos': {'robo': 3},
        'franja': {'desde': 18, 'hasta': 21},
      },
    ],
  },
};

void main() {
  test('pide /v1/map/heat con el bbox y la ventana', () async {
    final adapter = FakeHttpAdapter(200, _respuesta);

    final map = await HttpHeatRepository(
      fakeDio(adapter),
    ).fetch(_bbox, HeatWindow.week);

    expect(adapter.last!.method, 'GET');
    expect(adapter.last!.path, '/v1/map/heat');
    expect(adapter.last!.queryParameters, {
      'bbox': _bbox.toQuery(),
      'ventana': '7d',
    });
    expect(map.cells.single.count, 3);
    expect(map.cells.single.tipos, {IncidentType.robo: 3});
  });

  test('es público: no manda Authorization', () async {
    final adapter = FakeHttpAdapter(200, _respuesta);

    await HttpHeatRepository(fakeDio(adapter)).fetch(_bbox, HeatWindow.day);

    expect(adapter.last!.headers.containsKey('authorization'), isFalse);
  });

  test('un error de la API -> ApiFailure con su código', () async {
    final adapter = FakeHttpAdapter(400, {
      'error': {'code': 'invalid_window', 'message': 'ventana inválida'},
    });

    await expectLater(
      HttpHeatRepository(fakeDio(adapter)).fetch(_bbox, HeatWindow.day),
      throwsA(
        isA<ApiFailure>().having((e) => e.code, 'code', 'invalid_window'),
      ),
    );
  });

  test('sin conexión -> ApiFailure network', () async {
    final adapter = FakeHttpAdapter(
      200,
      null,
      error: DioException(
        requestOptions: RequestOptions(path: '/v1/map/heat'),
        type: DioExceptionType.connectionError,
      ),
    );

    await expectLater(
      HttpHeatRepository(fakeDio(adapter)).fetch(_bbox, HeatWindow.day),
      throwsA(isA<ApiFailure>().having((e) => e.code, 'code', 'network')),
    );
  });

  test('una respuesta sin la forma esperada -> invalid_response', () async {
    for (final cuerpo in <Object?>[
      {'data': 'nada'},
      {'otra': 'cosa'},
      'texto suelto',
    ]) {
      final adapter = FakeHttpAdapter(200, cuerpo);

      await expectLater(
        HttpHeatRepository(fakeDio(adapter)).fetch(_bbox, HeatWindow.day),
        throwsA(
          isA<ApiFailure>().having((e) => e.code, 'code', 'invalid_response'),
        ),
        reason: '$cuerpo',
      );
    }
  });
}
