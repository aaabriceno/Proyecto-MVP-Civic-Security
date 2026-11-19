import 'dart:async';
import 'dart:typed_data';

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

  /// Cada foto subida: el id del reporte y los bytes.
  final uploads = <(String, Uint8List)>[];

  /// Si no es null, la siguiente subida de foto falla con esto.
  ApiFailure? photoFailure;

  /// Si no es null, las subidas esperan a que este completer termine.
  Completer<void>? photoGate;

  final _created = <String, Incident>{};

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
    final incident = Incident(
      id: 'id-${sent.length}',
      tipo: input.tipo,
      descripcion: input.descripcion?.trim().isEmpty ?? true
          ? null
          : input.descripcion!.trim(),
      position: LatLng(input.lat, input.lng),
      estado: IncidentStatus.sinVerificar,
      creadoEn: DateTime.now().toUtc(),
    );
    _created[incident.id] = incident;
    return incident;
  }

  @override
  Future<Incident> uploadPhoto(String incidentId, Uint8List jpeg) async {
    uploads.add((incidentId, jpeg));
    if (photoGate != null) await photoGate!.future;
    if (photoFailure != null) throw photoFailure!;
    final original = _created[incidentId]!;
    return Incident(
      id: original.id,
      tipo: original.tipo,
      descripcion: original.descripcion,
      position: original.position,
      estado: original.estado,
      creadoEn: original.creadoEn,
      tieneFoto: true,
    );
  }

  /// Cada voto enviado: el id del reporte, el voto y desde dónde.
  final votes = <(String, VoteValue, LatLng)>[];

  /// Lo que responde el siguiente voto (el reporte con sus contadores nuevos).
  Incident? voteResult;

  /// Si no es null, el siguiente voto falla con esto.
  ApiFailure? voteFailure;

  /// Si no es null, los votos esperan a que este completer termine.
  Completer<void>? voteGate;

  @override
  Future<Incident> vote(
    String incidentId,
    VoteValue value,
    LatLng position,
  ) async {
    votes.add((incidentId, value, position));
    if (voteGate != null) await voteGate!.future;
    if (voteFailure != null) throw voteFailure!;
    return voteResult!;
  }

  /// Lo que devuelve `fetchPhoto` por id de reporte.
  final photos = <String, Uint8List>{};

  /// Cuántas veces se pidió una foto.
  int photoFetches = 0;

  /// Si no es null, `fetchPhoto` espera a que este completer termine.
  Completer<void>? fetchGate;

  @override
  Future<Uint8List> fetchPhoto(String incidentId) async {
    photoFetches++;
    if (fetchGate != null) await fetchGate!.future;
    final bytes = photos[incidentId];
    if (bytes == null) {
      throw const ApiFailure(code: 'not_found', message: 'No encontrado');
    }
    return bytes;
  }
}
