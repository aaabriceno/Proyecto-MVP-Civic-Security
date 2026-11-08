import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/realtime/phoenix_channel.dart';
import '../data/incident_stream.dart';
import 'map_incidents_controller.dart';

/// Conecta el tiempo real con el mapa. Su estado es el de la conexión (para
/// mostrar "En vivo" / "Conectando…").
///
/// - Cada reporte nuevo que llega se pasa al mapa ([MapIncidentsController.onRealtime]).
/// - Cada vez que la conexión queda establecida (la primera vez y después de
///   cada caída) se vuelve a pedir el snapshot. Es la pieza clave de
///   confiabilidad: mientras no escuchábamos pudieron llegar reportes que el
///   canal no repite, y el snapshot los recupera. Además cubre la carrera del
///   arranque (reporte creado entre la carga inicial y la unión al canal).
class LiveMapController extends Notifier<RealtimeStatus> {
  @override
  RealtimeStatus build() {
    final stream = ref.watch(incidentStreamProvider);

    final incidentsSub = stream.incidents.listen(
      (incident) =>
          ref.read(mapIncidentsProvider.notifier).onRealtime(incident),
    );
    final statusSub = stream.statuses.listen((status) {
      state = status;
      if (status == RealtimeStatus.connected) {
        unawaited(ref.read(mapIncidentsProvider.notifier).refresh());
      }
    });

    ref.onDispose(() {
      unawaited(incidentsSub.cancel());
      unawaited(statusSub.cancel());
      stream.stop();
    });

    return stream.status;
  }

  void start() => ref.read(incidentStreamProvider).start();

  void stop() => ref.read(incidentStreamProvider).stop();
}

final liveMapProvider = NotifierProvider<LiveMapController, RealtimeStatus>(
  LiveMapController.new,
);
