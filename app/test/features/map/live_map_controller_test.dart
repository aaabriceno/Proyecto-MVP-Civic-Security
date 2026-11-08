import 'package:civic_security/core/realtime/phoenix_channel.dart';
import 'package:civic_security/features/incident/data/incident_repository.dart';
import 'package:civic_security/features/incident/domain/incident.dart';
import 'package:civic_security/features/map/data/incident_stream.dart';
import 'package:civic_security/features/map/presentation/live_map_controller.dart';
import 'package:civic_security/features/map/presentation/map_incidents_controller.dart';
import 'package:civic_security/features/report/domain/new_incident.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'fake_incident_stream.dart';

Incident _incident(String id, {LatLng? at}) => Incident(
  id: id,
  tipo: IncidentType.robo,
  descripcion: null,
  position: at ?? const LatLng(-16.4, -71.5),
  estado: IncidentStatus.sinVerificar,
  creadoEn: DateTime.utc(2026, 11, 7),
);

const _bbox = Bbox(
  minLng: -71.75,
  minLat: -16.6,
  maxLng: -71.4,
  maxLat: -16.25,
);

class _FakeRepo implements IncidentRepository {
  final calls = <Bbox>[];
  List<Incident> next = [];

  @override
  Future<Incident> create(
    NewIncident input, {
    required String idempotencyKey,
  }) => throw UnimplementedError();

  @override
  Future<List<Incident>> fetchSnapshot(Bbox bbox) async {
    calls.add(bbox);
    return next;
  }
}

Future<(ProviderContainer, FakeIncidentStream, _FakeRepo)> _setup() async {
  final stream = FakeIncidentStream();
  final repo = _FakeRepo();
  final container = ProviderContainer(
    overrides: [
      incidentStreamProvider.overrideWithValue(stream),
      incidentRepositoryProvider.overrideWithValue(repo),
    ],
  );
  addTearDown(container.dispose);

  // El mapa ya cargó su área visible (como al abrir la pantalla)
  container.read(liveMapProvider);
  await container.read(mapIncidentsProvider.notifier).load(_bbox);
  repo.calls.clear();
  return (container, stream, repo);
}

void main() {
  test('un incidente en vivo aparece en el mapa', () async {
    final (c, stream, _) = await _setup();

    stream.emit(_incident('nuevo'));
    await Future<void>.delayed(Duration.zero);

    expect(c.read(mapIncidentsProvider).incidents.map((i) => i.id), ['nuevo']);
  });

  test('uno fuera del área visible no aparece', () async {
    final (c, stream, _) = await _setup();

    stream.emit(_incident('lima', at: const LatLng(-12.0, -77.0)));
    await Future<void>.delayed(Duration.zero);

    expect(c.read(mapIncidentsProvider).incidents, isEmpty);
  });

  test('al conectar (o reconectar) se vuelve a pedir el snapshot', () async {
    final (c, stream, repo) = await _setup();
    repo.next = [_incident('perdido-mientras-no-escuchaba')];

    stream.setStatus(RealtimeStatus.connecting);
    await Future<void>.delayed(Duration.zero);
    expect(repo.calls, isEmpty, reason: 'conectando todavía no es conectado');

    stream.setStatus(RealtimeStatus.connected);
    await Future<void>.delayed(Duration.zero);
    expect(repo.calls, [_bbox]);
    expect(c.read(mapIncidentsProvider).incidents.map((i) => i.id), [
      'perdido-mientras-no-escuchaba',
    ]);

    // Se cae y vuelve: otra recarga
    stream.setStatus(RealtimeStatus.disconnected);
    stream.setStatus(RealtimeStatus.connected);
    await Future<void>.delayed(Duration.zero);
    expect(repo.calls, hasLength(2));
  });

  test('el estado del provider refleja el de la conexión', () async {
    final (c, stream, _) = await _setup();
    expect(c.read(liveMapProvider), RealtimeStatus.disconnected);

    stream.setStatus(RealtimeStatus.connected);
    await Future<void>.delayed(Duration.zero);
    expect(c.read(liveMapProvider), RealtimeStatus.connected);
  });

  test('start y stop se delegan a la conexión', () async {
    final (c, stream, _) = await _setup();

    c.read(liveMapProvider.notifier).start();
    c.read(liveMapProvider.notifier).stop();

    expect((stream.starts, stream.stops), (1, 1));
  });

  test('al liberar el provider se corta la conexión', () async {
    final (c, stream, _) = await _setup();
    final stopsBefore = stream.stops;

    c.dispose();

    expect(stream.stops, stopsBefore + 1);
  });
}
