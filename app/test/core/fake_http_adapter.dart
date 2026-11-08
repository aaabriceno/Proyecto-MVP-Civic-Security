import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Simula el servidor: devuelve siempre la misma respuesta y guarda la última
/// petición para poder comprobar qué se envió (ruta, método, cuerpo, cabeceras).
class FakeHttpAdapter implements HttpClientAdapter {
  FakeHttpAdapter(
    this.status,
    this.body, {
    this.headers = const {},
    this.error,
  });

  final int status;

  /// `null` para una respuesta vacía (p. ej. un 204); un `String` se envía tal
  /// cual y cualquier otra cosa se convierte a JSON.
  final Object? body;
  final Map<String, List<String>> headers;

  /// Si se indica, la petición falla con este error (p. ej. sin conexión).
  final DioException? error;

  RequestOptions? last;
  int calls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    last = options;
    if (error != null) throw error!;

    final text = switch (body) {
      null => '',
      final String s => s,
      final other => jsonEncode(other),
    };
    return ResponseBody.fromString(
      text,
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json; charset=utf-8'],
        ...headers,
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// Un [Dio] cuyas peticiones atiende [adapter] en lugar de la red.
Dio fakeDio(FakeHttpAdapter adapter) =>
    Dio(BaseOptions(baseUrl: 'http://test'))..httpClientAdapter = adapter;
