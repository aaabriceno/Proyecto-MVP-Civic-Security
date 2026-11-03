import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_failure.dart';
import '../../report/domain/new_incident.dart';
import '../domain/incident.dart';

/// De dónde salen los incidentes. Es una interfaz para poder reemplazarla por
/// un falso en los tests.
abstract interface class IncidentRepository {
  /// Incidentes de las últimas 24 h dentro de [bbox].
  /// Lanza [ApiFailure] si algo falla.
  Future<List<Incident>> fetchSnapshot(Bbox bbox);

  /// Crea un reporte anónimo. [idempotencyKey] evita duplicados si el envío
  /// se reintenta: el mismo reporte con la misma clave no se guarda dos veces.
  /// Lanza [ApiFailure] si algo falla.
  Future<Incident> create(NewIncident input, {required String idempotencyKey});
}

class HttpIncidentRepository implements IncidentRepository {
  HttpIncidentRepository(this._dio);

  final Dio _dio;

  @override
  Future<List<Incident>> fetchSnapshot(Bbox bbox) async {
    try {
      final response = await _dio.get<Object?>(
        '/v1/map/snapshot',
        queryParameters: {'bbox': bbox.toQuery()},
      );
      return _parse(response.data);
    } on DioException catch (e) {
      throw ApiFailure.fromDio(e);
    } on FormatException {
      throw const ApiFailure.invalidResponse();
    }
  }

  @override
  Future<Incident> create(
    NewIncident input, {
    required String idempotencyKey,
  }) async {
    try {
      final response = await _dio.post<Object?>(
        '/v1/incidents',
        data: input.toJson(),
        options: Options(headers: {'idempotency-key': idempotencyKey}),
      );
      final body = response.data;
      final data = body is Map ? body['data'] : null;
      final incident = data is Map<String, dynamic>
          ? Incident.tryFromJson(data)
          : null;
      if (incident == null) throw const ApiFailure.invalidResponse();
      return incident;
    } on DioException catch (e) {
      throw ApiFailure.fromDio(e);
    } on FormatException {
      throw const ApiFailure.invalidResponse();
    }
  }

  List<Incident> _parse(Object? body) {
    if (body is! Map || body['data'] is! Map) {
      throw const ApiFailure.invalidResponse();
    }
    final list = (body['data'] as Map)['incidentes'];
    if (list is! List) throw const ApiFailure.invalidResponse();

    return [
      for (final item in list)
        if (item is Map<String, dynamic>)
          ?Incident.tryFromJson(item)
        else
          throw const ApiFailure.invalidResponse(),
    ];
  }
}

final incidentRepositoryProvider = Provider<IncidentRepository>(
  (ref) => HttpIncidentRepository(ref.watch(dioProvider)),
);
