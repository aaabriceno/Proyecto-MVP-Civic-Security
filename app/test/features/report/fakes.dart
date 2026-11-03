import 'dart:async';

import 'package:civic_security/core/network/api_failure.dart';
import 'package:civic_security/features/incident/data/incident_repository.dart';
import 'package:civic_security/features/incident/domain/incident.dart';
import 'package:civic_security/features/report/domain/new_incident.dart';
import 'package:latlong2/latlong.dart';

/// Repositorio falso para los tests del reporte: guarda cada intento de envío.
class ReportFakeRepo implements IncidentRepository {
  final sent = <(NewIncident, String)>[];

  /// Si no es null, el siguiente envío falla con esto.
  ApiFailure? failure;

  /// Si no es null, los envíos esperan a que este completer termine.
  Completer<void>? gate;

  @override
  Future<List<Incident>> fetchSnapshot(Bbox bbox) async => const [];

  @override
  Future<Incident> create(
    NewIncident input, {
    required String idempotencyKey,
  }) async {
    sent.add((input, idempotencyKey));
    if (gate != null) await gate!.future;
    if (failure != null) throw failure!;
    return Incident(
      id: 'id-${sent.length}',
      tipo: input.tipo,
      descripcion: input.descripcion?.trim().isEmpty ?? true
          ? null
          : input.descripcion!.trim(),
      position: LatLng(input.lat, input.lng),
      estado: IncidentStatus.sinVerificar,
      creadoEn: DateTime.now().toUtc(),
    );
  }
}
