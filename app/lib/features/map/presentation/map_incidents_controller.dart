import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_failure.dart';
import '../../incident/data/incident_repository.dart';
import '../../incident/domain/incident.dart';

class MapIncidentsState {
  const MapIncidentsState({
    this.incidents = const [],
    this.loading = false,
    this.failure,
  });

  final List<Incident> incidents;
  final bool loading;

  /// Último error al cargar; los [incidents] anteriores se conservan.
  final ApiFailure? failure;
}

/// Incidentes del área visible del mapa.
class MapIncidentsController extends Notifier<MapIncidentsState> {
  // Cada consulta lleva un número: solo la más reciente puede cambiar el estado
  int _lastRequest = 0;
  Bbox? _lastBbox;

  @override
  MapIncidentsState build() => const MapIncidentsState();

  Future<void> load(Bbox bbox) async {
    _lastBbox = bbox;
    final request = ++_lastRequest;
    state = MapIncidentsState(incidents: state.incidents, loading: true);

    try {
      final incidents = await ref
          .read(incidentRepositoryProvider)
          .fetchSnapshot(bbox);
      if (request != _lastRequest) return; // llegó tarde: ya hay otra consulta
      state = MapIncidentsState(incidents: incidents);
    } on ApiFailure catch (failure) {
      if (request != _lastRequest) return;
      state = MapIncidentsState(incidents: state.incidents, failure: failure);
    } on Object {
      if (request != _lastRequest) return;
      state = MapIncidentsState(
        incidents: state.incidents,
        failure: const ApiFailure.unexpected(),
      );
    }
  }

  /// Repite la última consulta (botón "Reintentar").
  Future<void> retry() async {
    final bbox = _lastBbox;
    if (bbox != null) await load(bbox);
  }

  /// Agrega un incidente (al frente, lo más nuevo primero) o lo reemplaza si
  /// ya existe. Lo usarán el reporte recién enviado y el tiempo real.
  void upsert(Incident incident) {
    final list = [...state.incidents];
    final index = list.indexWhere((i) => i.id == incident.id);
    if (index >= 0) {
      list[index] = incident;
    } else {
      list.insert(0, incident);
    }
    state = MapIncidentsState(
      incidents: list,
      loading: state.loading,
      failure: state.failure,
    );
  }
}

final mapIncidentsProvider =
    NotifierProvider<MapIncidentsController, MapIncidentsState>(
      MapIncidentsController.new,
    );

/// Tipo elegido en los chips de filtro; `null` muestra todos.
class TypeFilterController extends Notifier<IncidentType?> {
  @override
  IncidentType? build() => null;

  void select(IncidentType? type) => state = type;
}

final typeFilterProvider =
    NotifierProvider<TypeFilterController, IncidentType?>(
      TypeFilterController.new,
    );

/// Los incidentes cargados, ya filtrados por tipo.
final visibleIncidentsProvider = Provider<List<Incident>>((ref) {
  final all = ref.watch(mapIncidentsProvider.select((s) => s.incidents));
  final filter = ref.watch(typeFilterProvider);
  return filter == null
      ? all
      : [
          for (final i in all)
            if (i.tipo == filter) i,
        ];
});
