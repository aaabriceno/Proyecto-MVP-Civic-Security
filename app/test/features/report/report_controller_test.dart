import 'dart:async';

import 'package:civic_security/core/network/api_failure.dart';
import 'package:civic_security/features/incident/data/incident_repository.dart';
import 'package:civic_security/features/incident/domain/incident.dart';
import 'package:civic_security/features/map/presentation/map_incidents_controller.dart';
import 'package:civic_security/features/report/domain/new_incident.dart';
import 'package:civic_security/features/report/presentation/report_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

const _robo = NewIncident(
  tipo: IncidentType.robo,
  descripcion: 'x',
  lat: -16.4,
  lng: -71.5,
);
const _pelea = NewIncident(
  tipo: IncidentType.peleaColegio,
  descripcion: 'x',
  lat: -16.4,
  lng: -71.5,
);

(ProviderContainer, ReportFakeRepo) _setup() {
  final repo = ReportFakeRepo();
  final container = ProviderContainer(
    overrides: [incidentRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(container.dispose);
  // autoDispose: se mantiene viva mientras dura el test
  container.listen(reportControllerProvider, (_, _) {});
  return (container, repo);
}

void main() {
  test('envía el reporte con una clave de idempotencia (UUID)', () async {
    final (c, repo) = _setup();
    await c.read(reportControllerProvider.notifier).submit(_robo);

    expect(repo.sent.single.$1, _robo);
    expect(
      repo.sent.single.$2,
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
  });

  test('si sale bien, guarda el incidente y lo agrega al mapa', () async {
    final (c, _) = _setup();
    await c.read(reportControllerProvider.notifier).submit(_robo);

    final s = c.read(reportControllerProvider);
    expect(s.created, isNotNull);
    expect(s.sending, isFalse);
    expect(s.failure, isNull);
    expect(c.read(mapIncidentsProvider).incidents.map((i) => i.id), [
      s.created!.id,
    ]);
  });

  test('si falla, expone el error y no toca el mapa', () async {
    final (c, repo) = _setup();
    repo.failure = const ApiFailure.network();
    await c.read(reportControllerProvider.notifier).submit(_robo);

    final s = c.read(reportControllerProvider);
    expect(s.failure?.code, 'network');
    expect(s.created, isNull);
    expect(s.sending, isFalse);
    expect(c.read(mapIncidentsProvider).incidents, isEmpty);
  });

  test('reintentar el mismo reporte reusa la clave (no se duplica)', () async {
    final (c, repo) = _setup();
    final n = c.read(reportControllerProvider.notifier);

    repo.failure = const ApiFailure.network();
    await n.submit(_robo);
    repo.failure = null;
    await n.submit(_robo);

    expect(repo.sent.length, 2);
    expect(repo.sent[0].$2, repo.sent[1].$2);
  });

  test(
    'cambiar el contenido tras un fallo es otro reporte: clave nueva',
    () async {
      final (c, repo) = _setup();
      final n = c.read(reportControllerProvider.notifier);

      repo.failure = const ApiFailure.network();
      await n.submit(_robo);
      repo.failure = null;
      await n.submit(_pelea);

      expect(repo.sent[0].$2, isNot(repo.sent[1].$2));
    },
  );

  test('un doble toque mientras envía se ignora', () async {
    final (c, repo) = _setup();
    repo.gate = Completer<void>();
    final n = c.read(reportControllerProvider.notifier);

    final primero = n.submit(_robo);
    expect(c.read(reportControllerProvider).sending, isTrue);
    await n.submit(_robo); // segundo toque
    expect(repo.sent.length, 1);

    repo.gate!.complete();
    await primero;
    expect(c.read(reportControllerProvider).created, isNotNull);
  });

  test('tras enviar bien, otro envío se ignora', () async {
    final (c, repo) = _setup();
    final n = c.read(reportControllerProvider.notifier);
    await n.submit(_robo);
    await n.submit(_robo);
    expect(repo.sent.length, 1);
  });

  test('un error inesperado se convierte en ApiFailure', () async {
    final repo = _Boom();
    final c = ProviderContainer(
      overrides: [incidentRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(c.dispose);
    c.listen(reportControllerProvider, (_, _) {});

    await c.read(reportControllerProvider.notifier).submit(_robo);
    expect(c.read(reportControllerProvider).failure?.code, 'unexpected');
  });
}

class _Boom implements IncidentRepository {
  @override
  Future<List<Incident>> fetchSnapshot(Bbox bbox) async => const [];

  @override
  Future<Incident> create(
    NewIncident input, {
    required String idempotencyKey,
  }) => throw StateError('boom');
}
