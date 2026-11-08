import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'socket_connection.dart';

/// Estado de la conexión en vivo.
enum RealtimeStatus { disconnected, connecting, connected }

/// Un evento que el servidor empujó por el canal (por ejemplo
/// `incidente_nuevo`).
class PhoenixEvent {
  const PhoenixEvent(this.event, this.payload);

  final String event;
  final Map<String, dynamic> payload;
}

/// Convierte la `API_URL` (http/https) en la dirección del WebSocket de
/// Phoenix (ws/wss). `https` pasa a `wss`, así el cifrado se hereda de la API.
Uri realtimeUrl(String apiUrl) {
  final base = Uri.parse(apiUrl);
  final scheme = switch (base.scheme) {
    'http' => 'ws',
    'https' => 'wss',
    _ => throw ArgumentError.value(
      apiUrl,
      'apiUrl',
      'debe empezar con http:// o https://',
    ),
  };
  final prefix = base.path.replaceAll(RegExp(r'/+$'), '');
  return Uri(
    scheme: scheme,
    host: base.host,
    port: base.hasPort ? base.port : null,
    path: '$prefix/socket/websocket',
    queryParameters: {'vsn': '2.0.0'},
  );
}

final _random = Random();

/// Espera antes de reintentar: 1 s, 2 s, 4 s... hasta 30 s, con ±25 % de azar.
/// El azar evita que miles de teléfonos reconecten todos a la vez cuando el
/// servidor vuelve (y el tope evita esperas absurdas).
Duration defaultBackoff(int attempt) {
  final baseMs = (1000 * (1 << min(attempt, 10))).clamp(1000, 30000);
  final jitter = 0.75 + _random.nextDouble() * 0.5;
  return Duration(milliseconds: (baseMs * jitter).round());
}

/// Estado de UNA conexión. Cada reintento crea una sesión nueva; así, los
/// avisos tardíos de una conexión vieja (que ya descartamos) se ignoran.
class _Session {
  SocketConnection? connection;
  StreamSubscription<String>? subscription;
  Timer? joinTimer;
  Timer? heartbeatTimer;
  String? joinRef;
  String? pendingHeartbeat;
  bool joined = false;
}

/// Cliente mínimo del protocolo de canales de Phoenix (serializador v2.0.0)
/// para UN tópico de solo lectura.
///
/// Cada mensaje es una lista JSON de 5 elementos:
///
///     [join_ref, ref, topic, event, payload]
///
/// Lo que hace:
/// 1. Abre el WebSocket y manda `phx_join` para suscribirse al tópico.
/// 2. Cuando el servidor contesta `ok`, queda [RealtimeStatus.connected].
/// 3. Manda un `heartbeat` cada [heartbeatEvery]; si el anterior no fue
///    respondido, da la conexión por muerta (pasa con túneles, apagones de
///    wifi, cambio de red: el sistema no avisa que el socket murió).
/// 4. Si la conexión cae, reintenta con espera creciente ([backoff]).
///
/// No envía nada más: los clientes solo escuchan.
class PhoenixChannel {
  PhoenixChannel({
    required this.url,
    required this.topic,
    SocketConnector? connector,
    this.heartbeatEvery = const Duration(seconds: 30),
    this.joinTimeout = const Duration(seconds: 10),
    Duration Function(int attempt)? backoff,
    this.maxFrameChars = 16 * 1024,
  }) : _connector = connector ?? connectWebSocket,
       _backoff = backoff ?? defaultBackoff;

  final Uri url;
  final String topic;
  final Duration heartbeatEvery;
  final Duration joinTimeout;

  /// Tamaño máximo (en caracteres) de un mensaje del servidor; lo mayor se
  /// descarta sin procesarlo.
  final int maxFrameChars;

  final SocketConnector _connector;
  final Duration Function(int attempt) _backoff;

  final _events = StreamController<PhoenixEvent>.broadcast();
  final _statuses = StreamController<RealtimeStatus>.broadcast();

  RealtimeStatus _status = RealtimeStatus.disconnected;
  _Session? _session;
  Timer? _retryTimer;
  bool _wanted = false; // el usuario pidió estar conectado
  bool _disposed = false;
  int _attempt = 0; // fallos seguidos, para calcular la espera
  int _ref = 0;

  RealtimeStatus get status => _status;

  /// Eventos del tópico (sin los mensajes internos del protocolo).
  Stream<PhoenixEvent> get events => _events.stream;

  /// Cambios de estado (sin repetir el mismo dos veces seguidas).
  Stream<RealtimeStatus> get statuses => _statuses.stream;

  /// Empieza a conectar (y a reconectar solo). Si ya se pidió, no hace nada.
  void connect() {
    if (_disposed || _wanted) return;
    _wanted = true;
    _open();
  }

  /// Corta la conexión y deja de reintentar. No espera el cierre del
  /// WebSocket (con un servidor mudo ese cierre puede tardar): la app ya no
  /// escucha desde este momento.
  void disconnect() {
    _wanted = false;
    _retryTimer?.cancel();
    _retryTimer = null;
    final session = _session;
    _session = null;
    _setStatus(RealtimeStatus.disconnected);
    if (session != null) _teardown(session);
  }

  void dispose() {
    disconnect();
    _disposed = true;
    unawaited(_events.close());
    unawaited(_statuses.close());
  }

  void _open() {
    final session = _session = _Session();
    _setStatus(RealtimeStatus.connecting);
    _connector(url).then(
      (connection) => _onConnected(session, connection),
      onError: (Object _) => _lost(session),
    );
  }

  void _onConnected(_Session session, SocketConnection connection) {
    if (_session != session) {
      // Se desconectó mientras el socket abría: se cierra sin usarlo
      unawaited(_closeQuietly(connection));
      return;
    }
    session.connection = connection;
    session.subscription = connection.messages.listen(
      (text) => _onMessage(session, text),
      onError: (Object _) => _lost(session),
      onDone: () => _lost(session),
      cancelOnError: true,
    );
    session.joinRef = _nextRef();
    _send(session, [
      session.joinRef,
      session.joinRef,
      topic,
      'phx_join',
      <String, Object?>{},
    ]);
    session.joinTimer = Timer(joinTimeout, () => _lost(session));
  }

  void _onMessage(_Session session, String text) {
    if (_session != session || text.length > maxFrameChars) return;

    final Object? frame;
    try {
      frame = jsonDecode(text);
    } on FormatException {
      return;
    }
    if (frame is! List || frame.length != 5) return;

    final ref = frame[1];
    final messageTopic = frame[2];
    final event = frame[3];
    final payload = frame[4];
    if (messageTopic is! String ||
        event is! String ||
        payload is! Map<String, dynamic>) {
      return;
    }

    // Respuesta a un heartbeat: la conexión está viva
    if (messageTopic == 'phoenix') {
      if (event == 'phx_reply' && ref == session.pendingHeartbeat) {
        session.pendingHeartbeat = null;
      }
      return;
    }
    if (messageTopic != topic) return;

    switch (event) {
      case 'phx_reply':
        if (!session.joined && ref == session.joinRef) {
          payload['status'] == 'ok' ? _onJoined(session) : _lost(session);
        }
      case 'phx_error' || 'phx_close':
        _lost(session);
      default:
        // El servidor solo empuja eventos después de aceptar el join
        if (session.joined) _events.add(PhoenixEvent(event, payload));
    }
  }

  void _onJoined(_Session session) {
    session.joined = true;
    session.joinTimer?.cancel();
    _attempt = 0; // la conexión fue buena: la próxima espera vuelve a ser corta
    _setStatus(RealtimeStatus.connected);
    session.heartbeatTimer = Timer.periodic(
      heartbeatEvery,
      (_) => _heartbeat(session),
    );
  }

  void _heartbeat(_Session session) {
    if (_session != session) return;
    if (session.pendingHeartbeat != null) {
      _lost(session); // el latido anterior nunca fue respondido
      return;
    }
    final ref = session.pendingHeartbeat = _nextRef();
    _send(session, [null, ref, 'phoenix', 'heartbeat', <String, Object?>{}]);
  }

  void _send(_Session session, List<Object?> frame) {
    try {
      session.connection?.send(jsonEncode(frame));
    } on Object {
      _lost(session);
    }
  }

  /// La conexión se perdió (o fue rechazada). Limpia y agenda el reintento.
  void _lost(_Session session) {
    if (_session != session) return; // ya fue atendida
    _session = null;
    _teardown(session);
    _setStatus(RealtimeStatus.disconnected);

    if (_wanted && !_disposed) {
      final wait = _backoff(_attempt++);
      _retryTimer = Timer(wait, () {
        _retryTimer = null;
        if (_wanted && !_disposed) _open();
      });
    }
  }

  /// Apaga timers, deja de escuchar y pide cerrar el socket. Nada de esto se
  /// espera: lo que tarde el cierre no debe frenar a quien llama.
  void _teardown(_Session session) {
    session.joinTimer?.cancel();
    session.heartbeatTimer?.cancel();
    unawaited(session.subscription?.cancel());
    final connection = session.connection;
    if (connection != null) unawaited(_closeQuietly(connection));
  }

  Future<void> _closeQuietly(SocketConnection connection) async {
    try {
      await connection.close();
    } on Object {
      // Ya estaba cerrada: no es un error
    }
  }

  String _nextRef() => '${++_ref}';

  void _setStatus(RealtimeStatus status) {
    if (_status == status) return;
    _status = status;
    if (!_disposed) _statuses.add(status);
  }
}
