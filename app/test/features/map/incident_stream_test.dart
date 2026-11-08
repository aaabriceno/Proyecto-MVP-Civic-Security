import 'package:civic_security/core/realtime/phoenix_channel.dart';
import 'package:civic_security/features/incident/domain/incident.dart';
import 'package:civic_security/features/map/data/incident_stream.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../core/fake_socket.dart';

/// Lo que el servidor manda en `incidente_nuevo` (mismo JSON que el snapshot).
Map<String, Object?> _payload({
  String id = 'a1',
  String tipo = 'robo',
  Object? lat = -16.4,
  Object? lng = -71.5,
}) => {
  'id': id,
  'tipo': tipo,
  'descripcion': 'Me robaron el celular',
  'lat': lat,
  'lng': lng,
  'estado': 'sin_verificar',
  'creado_en': '2026-11-07T15:30:00.000000Z',
};

void _streamTest(
  String description,
  Future<void> Function(
    WidgetTester tester,
    FakeNetwork net,
    PhoenixIncidentStream stream,
  )
  body,
) {
  testWidgets(description, (tester) async {
    final net = FakeNetwork();
    final stream = PhoenixIncidentStream(
      PhoenixChannel(
        url: Uri.parse('ws://x/socket/websocket?vsn=2.0.0'),
        topic: mapTopic,
        connector: net.connector,
        backoff: (_) => const Duration(seconds: 1),
      ),
    );
    try {
      await body(tester, net, stream);
    } finally {
      stream.dispose();
    }
  });
}

Future<FakeConnection> _start(
  WidgetTester tester,
  FakeNetwork net,
  PhoenixIncidentStream stream,
) async {
  stream.start();
  final conn = net.accept();
  await tester.pump();
  conn.acceptJoin();
  await tester.pump();
  return conn;
}

void main() {
  test('el tópico es el que emite el backend', () {
    expect(mapTopic, 'mapa:arequipa');
  });

  _streamTest('convierte incidente_nuevo en un Incident', (
    tester,
    net,
    stream,
  ) async {
    final received = <Incident>[];
    stream.incidents.listen(received.add);
    final conn = await _start(tester, net, stream);

    conn.serverSends([null, null, mapTopic, 'incidente_nuevo', _payload()]);
    await tester.pump();

    expect(received, hasLength(1));
    final incident = received.single;
    expect(incident.id, 'a1');
    expect(incident.tipo, IncidentType.robo);
    expect(incident.estado, IncidentStatus.sinVerificar);
    expect(
      (incident.position.latitude, incident.position.longitude),
      (-16.4, -71.5),
    );
    expect(incident.creadoEn, DateTime.utc(2026, 11, 7, 15, 30));
  });

  _streamTest('descarta lo que no entiende sin romper la conexión', (
    tester,
    net,
    stream,
  ) async {
    final received = <Incident>[];
    stream.incidents.listen(received.add);
    final conn = await _start(tester, net, stream);

    conn
      // tipo que esta versión de la app no conoce
      ..serverSends([
        null,
        null,
        mapTopic,
        'incidente_nuevo',
        _payload(tipo: 'tipo_del_futuro'),
      ])
      // lat con tipo equivocado (JSON malformado)
      ..serverSends([
        null,
        null,
        mapTopic,
        'incidente_nuevo',
        _payload(lat: 'norte'),
      ])
      // evento que la app no escucha
      ..serverSends([null, null, mapTopic, 'otra_cosa', _payload()])
      // uno bueno al final, para confirmar que el flujo sigue vivo
      ..serverSends([
        null,
        null,
        mapTopic,
        'incidente_nuevo',
        _payload(id: 'ok'),
      ]);
    await tester.pump();

    expect(received.map((i) => i.id), ['ok']);
    expect(stream.status, RealtimeStatus.connected);
  });

  _streamTest('reexpone el estado de la conexión', (tester, net, stream) async {
    final states = <RealtimeStatus>[];
    stream.statuses.listen(states.add);

    final conn = await _start(tester, net, stream);
    conn.serverCloses();
    await tester.pump();

    expect(states, [
      RealtimeStatus.connecting,
      RealtimeStatus.connected,
      RealtimeStatus.disconnected,
    ]);
  });

  _streamTest('stop corta la conexión y start la vuelve a abrir', (
    tester,
    net,
    stream,
  ) async {
    final conn = await _start(tester, net, stream);

    stream.stop();
    await tester.pump();
    expect(conn.closedByClient, isTrue);
    expect(stream.status, RealtimeStatus.disconnected);

    stream.start();
    expect(net.attempts, 2);
  });
}
