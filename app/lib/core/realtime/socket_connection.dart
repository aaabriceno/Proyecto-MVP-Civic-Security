import 'dart:async';

import 'package:web_socket_channel/web_socket_channel.dart';

/// Una conexión de texto ya abierta con el servidor.
///
/// Es una interfaz mínima a propósito: [PhoenixChannel] solo necesita recibir
/// texto, enviar texto y cerrar. Así los tests usan una conexión falsa y el
/// resto de la app no depende de la librería de WebSockets.
abstract interface class SocketConnection {
  /// Mensajes de texto del servidor. Termina (o da error) si la conexión cae.
  Stream<String> get messages;

  void send(String text);

  Future<void> close();
}

/// Abre una conexión nueva; lanza una excepción si no puede.
typedef SocketConnector = Future<SocketConnection> Function(Uri url);

/// La conexión real, sobre `web_socket_channel`.
class WebSocketConnection implements SocketConnection {
  WebSocketConnection(this._channel);

  final WebSocketChannel _channel;

  // Los marcos binarios no existen en nuestro protocolo: se descartan
  @override
  Stream<String> get messages =>
      _channel.stream.where((m) => m is String).cast<String>();

  @override
  void send(String text) => _channel.sink.add(text);

  @override
  Future<void> close() => _channel.sink.close();
}

/// Conector de producción: espera a que el WebSocket esté realmente abierto
/// (`ready`) antes de entregarlo; si el servidor no responde, lanza.
Future<SocketConnection> connectWebSocket(Uri url) async {
  final channel = WebSocketChannel.connect(url);
  await channel.ready;
  return WebSocketConnection(channel);
}
