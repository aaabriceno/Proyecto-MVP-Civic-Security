import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/network/api_failure.dart';
import '../../incident/data/incident_repository.dart';
import '../../incident/domain/incident.dart';
import '../../map/presentation/map_incidents_controller.dart';
import '../domain/new_incident.dart';

class ReportState {
  const ReportState({this.sending = false, this.failure, this.created});

  final bool sending;
  final ApiFailure? failure;

  /// El incidente ya guardado en el servidor.
  final Incident? created;
}

/// Envía un reporte. Hay uno por formulario abierto (se descarta al cerrarlo).
class ReportController extends Notifier<ReportState> {
  static const _uuid = Uuid();

  // La clave de idempotencia identifica UN reporte. Si la app reintenta el
  // mismo contenido (mala señal), el servidor no lo duplica; si el usuario lo
  // cambia, es otro reporte y se genera otra clave.
  String _key = _uuid.v4();
  NewIncident? _lastInput;

  @override
  ReportState build() => const ReportState();

  Future<void> submit(NewIncident input) async {
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
      state = ReportState(created: created);
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
}

final reportControllerProvider =
    NotifierProvider.autoDispose<ReportController, ReportState>(
      ReportController.new,
    );
