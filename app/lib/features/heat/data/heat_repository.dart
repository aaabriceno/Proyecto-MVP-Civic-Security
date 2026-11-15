import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_failure.dart';
import '../../incident/domain/incident.dart';
import '../domain/heat_map.dart';

/// De dónde sale el mapa de calor. Es una interfaz para poder reemplazarla por
/// un falso en los tests.
abstract interface class HeatRepository {
  /// La densidad de incidentes dentro de [bbox] en la [window] indicada.
  /// Lanza [ApiFailure] si algo falla.
  Future<HeatMap> fetch(Bbox bbox, HeatWindow window);
}

class HttpHeatRepository implements HeatRepository {
  HttpHeatRepository(this._dio);

  final Dio _dio;

  @override
  Future<HeatMap> fetch(Bbox bbox, HeatWindow window) async {
    try {
      final response = await _dio.get<Object?>(
        '/v1/map/heat',
        queryParameters: {'bbox': bbox.toQuery(), 'ventana': window.wire},
      );
      final body = response.data;
      if (body is! Map) throw const ApiFailure.invalidResponse();
      return HeatMap.fromJson(body['data']);
    } on DioException catch (e) {
      throw ApiFailure.fromDio(e);
    } on FormatException {
      throw const ApiFailure.invalidResponse();
    }
  }
}

final heatRepositoryProvider = Provider<HeatRepository>(
  (ref) => HttpHeatRepository(ref.watch(dioProvider)),
);
