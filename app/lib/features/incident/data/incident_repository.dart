import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_failure.dart';
import '../../../core/network/auth_interceptor.dart';
import '../../auth/data/session_dio.dart';
import '../../report/domain/new_incident.dart';
import '../domain/incident.dart';

/// De dónde salen los incidentes. Es una interfaz para poder reemplazarla por
/// un falso en los tests.
abstract interface class IncidentRepository {
  /// Incidentes de las últimas 24 h dentro de [bbox].
  /// Lanza [ApiFailure] si algo falla.
  Future<List<Incident>> fetchSnapshot(Bbox bbox);

  /// Crea un reporte. Exige sesión: el servidor no guarda quién lo hizo, pero
  /// necesita saber que es una cuenta (y cuánto le queda del cupo del día).
  /// [idempotencyKey] evita duplicados si el envío se reintenta: el mismo
  /// reporte con la misma clave no se guarda dos veces. Lanza [ApiFailure] si
  /// algo falla (`unauthorized` sin sesión, `report_quota_exceeded` sin cupo).
  Future<Incident> create(NewIncident input, {required String idempotencyKey});

  /// Sube la foto del reporte [incidentId] (un JPEG ya sin metadatos, ver
  /// `preparePhoto`). Solo puede quien lo reportó, y una sola vez. Devuelve el
  /// reporte con `tieneFoto`. Lanza [ApiFailure] (`not_author`, `photo_exists`,
  /// `photo_too_large`, `photo_has_metadata`...).
  Future<Incident> uploadPhoto(String incidentId, Uint8List jpeg);

  /// Los bytes de la foto de un reporte. Es pública, como el mapa: no manda la
  /// sesión. Lanza [ApiFailure] (`not_found` si no tiene foto).
  Future<Uint8List> fetchPhoto(String incidentId);
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
        options: conSesion(
          Options(headers: {'idempotency-key': idempotencyKey}),
        ),
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

  @override
  Future<Incident> uploadPhoto(String incidentId, Uint8List jpeg) async {
    try {
      final response = await _dio.put<Object?>(
        '/v1/incidents/$incidentId/photo',
        // La foto cruda, no JSON ni multipart
        data: jpeg,
        options: conSesion(Options(contentType: 'image/jpeg')),
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

  @override
  Future<Uint8List> fetchPhoto(String incidentId) async {
    try {
      final response = await _dio.get<List<int>>(
        '/v1/incidents/$incidentId/photo',
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = response.data;
      if (bytes == null || bytes.isEmpty) {
        throw const ApiFailure.invalidResponse();
      }
      return Uint8List.fromList(bytes);
    } on DioException catch (e) {
      throw ApiFailure.fromDio(_withDecodedError(e));
    }
  }

  /// Con `responseType: bytes`, el JSON de un error también llega como bytes:
  /// se decodifica para que `ApiFailure` lea su código.
  DioException _withDecodedError(DioException e) {
    final response = e.response;
    final data = response?.data;
    if (response == null || data is! List<int>) return e;
    try {
      final decoded = jsonDecode(utf8.decode(data));
      return e.copyWith(response: response..data = decoded);
    } on Object {
      return e.copyWith(response: response..data = null);
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
  (ref) => HttpIncidentRepository(ref.watch(sessionDioProvider)),
);
