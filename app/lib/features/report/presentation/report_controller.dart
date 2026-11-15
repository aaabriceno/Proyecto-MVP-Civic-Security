import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/network/api_failure.dart';
import '../../incident/data/incident_repository.dart';
import '../../incident/domain/incident.dart';
import '../../map/presentation/map_incidents_controller.dart';
import '../domain/new_incident.dart';

/// Cómo va la foto del reporte (si se adjuntó una).
enum PhotoStatus { none, uploading, uploaded, failed }

class ReportState {
  const ReportState({
    this.sending = false,
    this.failure,
    this.created,
    this.photo = PhotoStatus.none,
    this.photoFailure,
  });

  final bool sending;
  final ApiFailure? failure;

  /// El incidente ya guardado en el servidor.
  final Incident? created;

  /// La foto se sube **después** de crear el reporte: si falla, el reporte ya
  /// existe y solo se reintenta la foto.
  final PhotoStatus photo;
  final ApiFailure? photoFailure;
}

/// Envía un reporte. Hay uno por formulario abierto (se descarta al cerrarlo).
class ReportController extends Notifier<ReportState> {
  static const _uuid = Uuid();

  // La clave de idempotencia identifica UN reporte. Si la app reintenta el
  // mismo contenido (mala señal), el servidor no lo duplica; si el usuario lo
  // cambia, es otro reporte y se genera otra clave.
  String _key = _uuid.v4();
  NewIncident? _lastInput;

  // La foto ya preparada, guardada para poder reintentar su subida
  Uint8List? _photo;

  @override
  ReportState build() => const ReportState();

  Future<void> submit(NewIncident input, {Uint8List? photo}) async {
    // Un doble toque, o enviar de nuevo algo ya enviado, no hace nada
    if (state.sending || state.created != null) return;

    if (input != _lastInput) {
      _key = _uuid.v4();
      _lastInput = input;
    }
    state = const ReportState(sending: true);

    try {
      final created = await ref
          .read(incidentRepositoryProvider)
          .create(input, idempotencyKey: _key);
      if (!ref.mounted) return;
      ref.read(mapIncidentsProvider.notifier).upsert(created);
      _photo = photo;
      state = ReportState(
        created: created,
        photo: photo == null ? PhotoStatus.none : PhotoStatus.uploading,
      );
      if (photo != null) await _uploadPhoto(created);
    } on ApiFailure catch (failure) {
      if (ref.mounted) {
        state = ReportState(failure: failure);
      }
    } on Object {
      if (ref.mounted) {
        state = const ReportState(failure: ApiFailure.unexpected());
      }
    }
  }

  /// Sube otra vez la foto de un reporte que ya se creó (tras un fallo). No hace
  /// nada si no hay foto, si ya se subió o si ya se está subiendo.
  Future<void> retryPhoto() async {
    final created = state.created;
    if (created == null || _photo == null) return;
    if (state.photo != PhotoStatus.failed) return;

    state = ReportState(created: created, photo: PhotoStatus.uploading);
    await _uploadPhoto(created);
  }

  Future<void> _uploadPhoto(Incident created) async {
    try {
      final updated = await ref
          .read(incidentRepositoryProvider)
          .uploadPhoto(created.id, _photo!);
      _photoUploaded(updated);
    } on ApiFailure catch (failure) {
      // "Ya tiene foto": una subida anterior sí llegó y solo se perdió la
      // respuesta. La foto está, así que cuenta como subida.
      if (failure.code == 'photo_exists') {
        _photoUploaded(created.copyWith(tieneFoto: true));
      } else {
        _photoFailed(created, failure);
      }
    } on Object {
      _photoFailed(created, const ApiFailure.unexpected());
    }
  }

  void _photoUploaded(Incident updated) {
    if (!ref.mounted) return;
    ref.read(mapIncidentsProvider.notifier).upsert(updated);
    state = ReportState(created: updated, photo: PhotoStatus.uploaded);
  }

  void _photoFailed(Incident created, ApiFailure failure) {
    if (!ref.mounted) return;
    state = ReportState(
      created: created,
      photo: PhotoStatus.failed,
      photoFailure: failure,
    );
  }
}

final reportControllerProvider =
    NotifierProvider.autoDispose<ReportController, ReportState>(
      ReportController.new,
    );
