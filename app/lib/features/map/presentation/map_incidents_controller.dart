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

  /// Vuelve a pedir el área actual en segundo plano: sin "cargando" y sin
  /// mostrar error si falla. Se usa al (re)conectar el tiempo real, para
  /// recuperar lo que pasó mientras no estábamos escuchando.
  Future<void> refresh() async {
    final bbox = _lastBbox;
    if (bbox == null) return; // el mapa aún no pidió nada: no hay qué refrescar
    final request = ++_lastRequest;

    try {
      final incidents = await ref
          .read(incidentRepositoryProvider)
          .fetchSnapshot(bbox);
      if (request != _lastRequest) return;
      state = MapIncidentsState(incidents: incidents);
    } on Object {
      if (request != _lastRequest) return;
      // Conserva lo que había; pone loading en false por si este refresh
      // invalidó un load() que estaba en curso
      state = MapIncidentsState(
        incidents: state.incidents,
        failure: state.failure,
      );
    }
  }

  /// Un incidente llegó por el canal en vivo. Solo se agrega si cae dentro del
  /// área que el usuario está viendo: el canal cubre toda Arequipa, y lo de
  /// otras zonas se cargará cuando el usuario se mueva hacia allá.
  void onRealtime(Incident incident) {
    final bbox = _lastBbox;
    if (bbox == null || !bbox.contains(incident.position)) return;
    upsert(incident);
  }

  /// Igual que el límite del snapshot del servidor (`GET /v1/map/snapshot`).
  static const maxIncidents = 500;

  /// Agrega un incidente (al frente, lo más nuevo primero) o lo reemplaza si
  /// ya existe. Lo usan el reporte recién enviado y el tiempo real. La lista
  /// nunca pasa de [maxIncidents]: lo más viejo se descarta.
  void upsert(Incident incident) {
    final list = [...state.incidents];
    final index = list.indexWhere((i) => i.id == incident.id);
    if (index >= 0) {
      list[index] = incident;
    } else {
      list.insert(0, incident);
      if (list.length > maxIncidents) {
        list.removeRange(maxIncidents, list.length);
      }
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
