import 'dart:async';
import 'dart:convert';

import 'package:civic_security/core/realtime/socket_connection.dart';

/// Conexión falsa: guarda lo que la app envía y deja al test hablar como si
/// fuera el servidor.
class FakeConnection implements SocketConnection {
  final _incoming = StreamController<String>();

  /// Marcos que la app mandó, ya decodificados.
  final sent = <List<Object?>>[];
  bool closedByClient = false;

  @override
  Stream<String> get messages => _incoming.stream;

  @override
  void send(String text) => sent.add(jsonDecode(text) as List<Object?>);

  @override
  Future<void> close() async {
    closedByClient = true;
    // close() de un StreamController sin oyente no completa: no se espera
    if (!_incoming.isClosed) unawaited(_incoming.close());
  }

  void serverSends(List<Object?> frame) => _incoming.add(jsonEncode(frame));
  void serverSendsRaw(String raw) => _incoming.add(raw);
  void serverCloses() => _incoming.close();

  /// El marco de unión que mandó la app.
  List<Object?> get join => sent.firstWhere((f) => f[3] == 'phx_join');

  /// Responde "ok" al join, igual que Phoenix.
  void acceptJoin() => serverSends([
    join[0],
    join[1],
    join[2],
    'phx_reply',
    {'status': 'ok', 'response': <String, Object?>{}},
  ]);

  List<List<Object?>> get heartbeats =>
      sent.where((f) => f[3] == 'heartbeat').toList();
}

/// "Red" falsa: cada intento de conexión espera a que el test lo acepte o lo
/// rechace.
class FakeNetwork {
  final urls = <Uri>[];
  final _pending = <Completer<SocketConnection>>[];

  int get attempts => urls.length;

  Future<SocketConnection> connector(Uri url) {
    urls.add(url);
    final c = Completer<SocketConnection>();
    _pending.add(c);
    return c.future;
  }

  FakeConnection accept() {
    final conn = FakeConnection();
    _pending.removeLast().complete(conn);
    return conn;
  }

  void refuse() => _pending.removeLast().completeError(Exception('sin red'));
}
