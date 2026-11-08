import 'package:civic_security/core/realtime/phoenix_channel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_socket.dart';

const _topic = 'mapa:arequipa';

final _url = Uri.parse('ws://10.0.2.2:4000/socket/websocket?vsn=2.0.0');

PhoenixChannel _channel(FakeNetwork net) => PhoenixChannel(
  url: _url,
  topic: _topic,
  connector: net.connector,
  heartbeatEvery: const Duration(seconds: 30),
  joinTimeout: const Duration(seconds: 10),
  backoff: (attempt) => Duration(seconds: 1 << attempt), // 1 s, 2 s, 4 s...
);

/// Deja correr los microtasks pendientes (entrega de mensajes del stream) y
/// avanza el reloj falso [d].
Future<void> _flush(WidgetTester tester, [Duration d = Duration.zero]) =>
    tester.pump(d);

/// Un test con canal y red falsos. El canal se libera dentro del propio test
/// porque `flutter_test` revisa los timers pendientes antes de los tearDown.
void _channelTest(
  String description,
  Future<void> Function(WidgetTester tester, FakeNetwork net, PhoenixChannel ch)
  body,
) {
  testWidgets(description, (tester) async {
    final net = FakeNetwork();
    final ch = _channel(net);
    try {
      await body(tester, net, ch);
    } finally {
      ch.dispose();
    }
  });
}

/// Conecta y completa el join, como un arranque normal.
Future<FakeConnection> _connectAndJoin(
  WidgetTester tester,
  FakeNetwork net,
  PhoenixChannel ch,
) async {
  ch.connect();
  final conn = net.accept();
  await _flush(tester);
  conn.acceptJoin();
  await _flush(tester);
  return conn;
}

void main() {
  group('conexión y unión al tópico', () {
    _channelTest('al conectar manda phx_join y queda conectado con el ok', (
      tester,
      net,
      ch,
    ) async {
      expect(ch.status, RealtimeStatus.disconnected);
      ch.connect();
      expect(ch.status, RealtimeStatus.connecting);
      expect(net.urls.single, _url);

      final conn = net.accept();
      await _flush(tester);

      expect(conn.join[2], _topic);
      expect(conn.join[4], <String, Object?>{});
      expect(ch.status, RealtimeStatus.connecting, reason: 'falta el ok');

      conn.acceptJoin();
      await _flush(tester);
      expect(ch.status, RealtimeStatus.connected);
    });

    _channelTest('connect() repetido no abre una segunda conexión', (
      tester,
      net,
      ch,
    ) async {
      ch
        ..connect()
        ..connect();
      expect(net.attempts, 1);
    });

    _channelTest('si el join responde error, cierra y reintenta', (
      tester,
      net,
      ch,
    ) async {
      ch.connect();
      final conn = net.accept();
      await _flush(tester);

      conn.serverSends([
        conn.join[0],
        conn.join[1],
        _topic,
        'phx_reply',
        {
          'status': 'error',
          'response': {'reason': 'unauthorized'},
        },
      ]);
      await _flush(tester);

      expect(ch.status, RealtimeStatus.disconnected);
      expect(conn.closedByClient, isTrue);
      await _flush(tester, const Duration(seconds: 1));
      expect(net.attempts, 2, reason: 'reintenta tras la espera');
    });

    _channelTest('si el servidor nunca responde al join, vence y reintenta', (
      tester,
      net,
      ch,
    ) async {
      ch.connect();
      final conn = net.accept();
      await _flush(tester);

      await _flush(tester, const Duration(seconds: 10));
      expect(ch.status, RealtimeStatus.disconnected);
      expect(conn.closedByClient, isTrue);

      await _flush(tester, const Duration(seconds: 1));
      expect(net.attempts, 2);
    });
  });

  group('eventos recibidos', () {
    _channelTest('entrega los eventos del tópico', (tester, net, ch) async {
      final events = <PhoenixEvent>[];
      ch.events.listen(events.add);
      final conn = await _connectAndJoin(tester, net, ch);

      conn.serverSends([
        null,
        null,
        _topic,
        'incidente_nuevo',
        {'id': 'a', 'tipo': 'robo'},
      ]);
      await _flush(tester);

      expect(events, hasLength(1));
      expect(events.single.event, 'incidente_nuevo');
      expect(events.single.payload, {'id': 'a', 'tipo': 'robo'});
    });

    _channelTest('ignora otros tópicos y marcos malformados', (
      tester,
      net,
      ch,
    ) async {
      final events = <PhoenixEvent>[];
      ch.events.listen(events.add);
      final conn = await _connectAndJoin(tester, net, ch);

      conn
        ..serverSends([
          null,
          null,
          'mapa:cusco',
          'incidente_nuevo',
          <String, Object?>{},
        ])
        ..serverSendsRaw('esto no es json')
        ..serverSendsRaw('{"no":"una lista"}')
        ..serverSends([null, null, _topic, 'incidente_nuevo']) // faltan campos
        ..serverSends([null, null, _topic, 7, <String, Object?>{}]) // evento
        ..serverSends([null, null, _topic, 'incidente_nuevo', 'no es mapa'])
        ..serverSendsRaw('x' * 20000); // demasiado grande
      await _flush(tester);

      expect(events, isEmpty);
      expect(ch.status, RealtimeStatus.connected, reason: 'sigue conectado');
    });

    _channelTest('no entrega eventos antes de que el join sea aceptado', (
      tester,
      net,
      ch,
    ) async {
      final events = <PhoenixEvent>[];
      ch.events.listen(events.add);
      ch.connect();
      final conn = net.accept();
      await _flush(tester);

      conn.serverSends([
        null,
        null,
        _topic,
        'incidente_nuevo',
        <String, Object?>{'id': 'x'},
      ]);
      await _flush(tester);

      expect(events, isEmpty);
    });
  });

  group('latido', () {
    _channelTest('manda heartbeat cada intervalo y sigue si responden', (
      tester,
      net,
      ch,
    ) async {
      final conn = await _connectAndJoin(tester, net, ch);

      await _flush(tester, const Duration(seconds: 30));
      expect(conn.heartbeats, hasLength(1));
      expect(conn.heartbeats.single[2], 'phoenix');

      conn.serverSends([
        null,
        conn.heartbeats.single[1],
        'phoenix',
        'phx_reply',
        {'status': 'ok', 'response': <String, Object?>{}},
      ]);
      await _flush(tester);

      await _flush(tester, const Duration(seconds: 30));
      expect(conn.heartbeats, hasLength(2));
      expect(ch.status, RealtimeStatus.connected);
    });

    _channelTest(
      'si un heartbeat queda sin respuesta, da la conexión por muerta y '
      'reconecta',
      (tester, net, ch) async {
        final conn = await _connectAndJoin(tester, net, ch);

        // El 1.er latido sale y nadie responde
        await _flush(tester, const Duration(seconds: 30));
        expect(ch.status, RealtimeStatus.connected);
        // Al siguiente intervalo se da por muerta
        await _flush(tester, const Duration(seconds: 30));
        expect(ch.status, RealtimeStatus.disconnected);
        expect(conn.closedByClient, isTrue);

        await _flush(tester, const Duration(seconds: 1));
        expect(net.attempts, 2);
      },
    );
  });

  group('reconexión', () {
    _channelTest('si el servidor cierra, reintenta con espera creciente y la '
        'restablece al conectar', (tester, net, ch) async {
      var conn = await _connectAndJoin(tester, net, ch);

      // 1.ª caída: espera 1 s
      conn.serverCloses();
      await _flush(tester);
      expect(ch.status, RealtimeStatus.disconnected);
      await _flush(tester, const Duration(milliseconds: 900));
      expect(net.attempts, 1, reason: 'aún no pasa 1 s');
      await _flush(tester, const Duration(milliseconds: 200));
      expect(net.attempts, 2);

      // El reintento falla: ahora espera 2 s
      net.refuse();
      await _flush(tester);
      await _flush(tester, const Duration(milliseconds: 1900));
      expect(net.attempts, 2);
      await _flush(tester, const Duration(milliseconds: 200));
      expect(net.attempts, 3);

      // Conecta bien: el contador de fallos vuelve a cero
      conn = net.accept();
      await _flush(tester);
      conn.acceptJoin();
      await _flush(tester);
      expect(ch.status, RealtimeStatus.connected);

      conn.serverCloses();
      await _flush(tester);
      await _flush(tester, const Duration(seconds: 1));
      expect(net.attempts, 4, reason: 'volvió a esperar solo 1 s');
    });

    _channelTest('phx_close del canal también provoca reconexión', (
      tester,
      net,
      ch,
    ) async {
      final conn = await _connectAndJoin(tester, net, ch);

      conn.serverSends([null, null, _topic, 'phx_close', <String, Object?>{}]);
      await _flush(tester);
      expect(ch.status, RealtimeStatus.disconnected);

      await _flush(tester, const Duration(seconds: 1));
      expect(net.attempts, 2);
    });

    _channelTest('los cambios de estado se publican sin repetirse', (
      tester,
      net,
      ch,
    ) async {
      final states = <RealtimeStatus>[];
      ch.statuses.listen(states.add);

      final conn = await _connectAndJoin(tester, net, ch);
      conn.serverCloses();
      await _flush(tester);

      expect(states, [
        RealtimeStatus.connecting,
        RealtimeStatus.connected,
        RealtimeStatus.disconnected,
      ]);
    });
  });

  group('disconnect', () {
    _channelTest('cierra la conexión y no reintenta', (tester, net, ch) async {
      final conn = await _connectAndJoin(tester, net, ch);

      ch.disconnect();
      await _flush(tester);

      expect(ch.status, RealtimeStatus.disconnected);
      expect(conn.closedByClient, isTrue);
      await _flush(tester, const Duration(minutes: 5));
      expect(net.attempts, 1, reason: 'nadie volvió a conectar');
      expect(conn.heartbeats, isEmpty);
    });

    _channelTest(
      'si se desconecta mientras conecta, la conexión tardía se cierra y no '
      'se usa',
      (tester, net, ch) async {
        ch.connect();
        ch.disconnect();

        final late = net.accept(); // el socket abrió después de desconectar
        await _flush(tester);

        expect(late.closedByClient, isTrue);
        expect(late.sent, isEmpty, reason: 'no se unió al canal');
        expect(ch.status, RealtimeStatus.disconnected);
      },
    );

    _channelTest('se puede volver a conectar después de desconectar', (
      tester,
      net,
      ch,
    ) async {
      ch.connect();
      net.accept();
      await _flush(tester);
      ch.disconnect();

      ch.connect();
      expect(net.attempts, 2);
    });
  });

  group('realtimeUrl', () {
    test('http pasa a ws y https a wss', () {
      expect(
        realtimeUrl('http://10.0.2.2:4000').toString(),
        'ws://10.0.2.2:4000/socket/websocket?vsn=2.0.0',
      );
      expect(
        realtimeUrl('https://api.civic.pe').toString(),
        'wss://api.civic.pe/socket/websocket?vsn=2.0.0',
      );
    });

    test('tolera una barra final y conserva un prefijo de ruta', () {
      expect(
        realtimeUrl('https://api.civic.pe/').toString(),
        'wss://api.civic.pe/socket/websocket?vsn=2.0.0',
      );
      expect(
        realtimeUrl('https://civic.pe/api/').toString(),
        'wss://civic.pe/api/socket/websocket?vsn=2.0.0',
      );
    });

    test('rechaza esquemas que no sean http/https', () {
      expect(() => realtimeUrl('ftp://x'), throwsArgumentError);
    });
  });

  group('defaultBackoff', () {
    test('crece de forma exponencial, con tope y algo de azar', () {
      for (var attempt = 0; attempt < 12; attempt++) {
        final base = (1000 * (1 << attempt)).clamp(1000, 30000);
        final ms = defaultBackoff(attempt).inMilliseconds;
        expect(ms, greaterThanOrEqualTo((base * 0.75).floor()));
        expect(ms, lessThanOrEqualTo((base * 1.25).ceil()));
      }
    });
  });
}
