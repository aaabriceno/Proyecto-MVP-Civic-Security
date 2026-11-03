import 'dart:async';

import 'package:civic_security/core/network/api_failure.dart';
import 'package:civic_security/features/incident/data/incident_repository.dart';
import 'package:civic_security/features/incident/domain/incident.dart';
import 'package:civic_security/features/map/presentation/map_incidents_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

Incident _incident(String id) => Incident(
  id: id,
  tipo: IncidentType.robo,
  descripcion: null,
  position: const LatLng(-16.4, -71.5),
  estado: IncidentStatus.sinVerificar,
  creadoEn: DateTime.utc(2026, 11, 3),
);

const _bbox = Bbox(
  minLng: -71.75,
  minLat: -16.6,
  maxLng: -71.4,
  maxLat: -16.25,
);

/// Repositorio falso: cada llamada devuelve lo que el test decida.
class _FakeRepo implements IncidentRepository {
  final calls = <Bbox>[];
  final pending = <Completer<List<Incident>>>[];

  @override
  Future<List<Incident>> fetchSnapshot(Bbox bbox) {
    calls.add(bbox);
    final c = Completer<List<Incident>>();
    pending.add(c);
    return c.future;
  }
}

(ProviderContainer, _FakeRepo) _setup() {
  final repo = _FakeRepo();
  final container = ProviderContainer(
    overrides: [incidentRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(container.dispose);
  return (container, repo);
}

void main() {
  test('empieza vacío y sin cargar', () {
    final (c, _) = _setup();
    final s = c.read(mapIncidentsProvider);
    expect(s.incidents, isEmpty);
    expect(s.loading, isFalse);
    expect(s.failure, isNull);
  });

  test('load marca cargando y luego guarda los incidentes', () async {
    final (c, repo) = _setup();
    final f = c.read(mapIncidentsProvider.notifier).load(_bbox);

    expect(c.read(mapIncidentsProvider).loading, isTrue);
    repo.pending.single.complete([_incident('a'), _incident('b')]);
    await f;

    final s = c.read(mapIncidentsProvider);
    expect(s.loading, isFalse);
    expect(s.incidents.map((i) => i.id), ['a', 'b']);
    expect(repo.calls.single, _bbox);
  });

  test(
    'si falla, conserva los incidentes anteriores y expone el error',
    () async {
      final (c, repo) = _setup();
      final n = c.read(mapIncidentsProvider.notifier);

      final f1 = n.load(_bbox);
      repo.pending[0].complete([_incident('a')]);
      await f1;

      final f2 = n.load(_bbox);
      repo.pending[1].completeError(
        const ApiFailure(code: 'network', message: 'sin conexión'),
      );
      await f2;

      final s = c.read(mapIncidentsProvider);
      expect(
        s.incidents.map((i) => i.id),
        ['a'],
        reason: 'el mapa no se vacía por un error de red',
      );
      expect(s.failure?.code, 'network');
      expect(s.loading, isFalse);
    },
  );

  test('un error inesperado también se convierte en ApiFailure', () async {
    final (c, repo) = _setup();
    final f = c.read(mapIncidentsProvider.notifier).load(_bbox);
    repo.pending.single.completeError(StateError('algo raro'));
    await f;
    expect(c.read(mapIncidentsProvider).failure?.code, 'unexpected');
  });

  test('una respuesta lenta no pisa a una más nueva (carrera)', () async {
    final (c, repo) = _setup();
    final n = c.read(mapIncidentsProvider.notifier);

    final vieja = n.load(_bbox);
    final nueva = n.load(_bbox);
    repo.pending[1].complete([_incident('nueva')]);
    await nueva;
    repo.pending[0].complete([_incident('vieja')]);
    await vieja;

    expect(c.read(mapIncidentsProvider).incidents.map((i) => i.id), ['nueva']);
  });

  test('un error de una petición vieja tampoco pisa a una nueva', () async {
    final (c, repo) = _setup();
    final n = c.read(mapIncidentsProvider.notifier);

    final vieja = n.load(_bbox);
    final nueva = n.load(_bbox);
    repo.pending[1].complete([_incident('nueva')]);
    await nueva;
    repo.pending[0].completeError(
      const ApiFailure(code: 'network', message: 'x'),
    );
    await vieja;

    final s = c.read(mapIncidentsProvider);
    expect((s.incidents.length, s.failure), (1, null));
  });

  test('retry repite la última consulta', () async {
    final (c, repo) = _setup();
    final n = c.read(mapIncidentsProvider.notifier);

    final f1 = n.load(_bbox);
    repo.pending[0].completeError(
      const ApiFailure(code: 'network', message: 'x'),
    );
    await f1;

    final f2 = n.retry();
    repo.pending[1].complete([_incident('a')]);
    await f2;

    expect(repo.calls, [_bbox, _bbox]);
    final s = c.read(mapIncidentsProvider);
    expect((s.incidents.length, s.failure), (1, null));
  });

  test('retry sin consulta previa no hace nada', () async {
    final (c, repo) = _setup();
    await c.read(mapIncidentsProvider.notifier).retry();
    expect(repo.calls, isEmpty);
  });

  test('upsert inserta al frente y reemplaza en su sitio, sin duplicar', () {
    final (c, _) = _setup();
    final n = c.read(mapIncidentsProvider.notifier);

    n.upsert(_incident('a'));
    n.upsert(_incident('b'));
    n.upsert(_incident('a'));

    expect(c.read(mapIncidentsProvider).incidents.map((i) => i.id), ['b', 'a']);
  });
}
