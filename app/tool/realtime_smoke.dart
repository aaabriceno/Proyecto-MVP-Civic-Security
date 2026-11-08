// Prueba de humo del tiempo real contra un servidor de verdad (sin fakes).
//
// Usa el mismo PhoenixChannel que la app: se une a `mapa:arequipa`, crea un
// reporte por la API REST y comprueba que el evento `incidente_nuevo` llegue
// por el WebSocket. Con --watch se queda escuchando para probar la reconexión
// (apaga y vuelve a levantar el servidor mientras corre).
//
//     cd app
//     dart run tool/realtime_smoke.dart                 # una vez
//     dart run tool/realtime_smoke.dart --watch         # queda escuchando
//     dart run tool/realtime_smoke.dart http://127.0.0.1:4000

// Es una herramienta de consola: imprimir es su trabajo
// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:civic_security/core/realtime/phoenix_channel.dart';
import 'package:uuid/uuid.dart';

Future<void> main(List<String> args) async {
  final watch = args.contains('--watch');
  final api =
      args.where((a) => !a.startsWith('--')).firstOrNull ??
      'http://127.0.0.1:4000';

  final channel = PhoenixChannel(url: realtimeUrl(api), topic: 'mapa:arequipa');
  final received = <PhoenixEvent>[];

  channel.statuses.listen((s) => print('[${_hora()}] estado: ${s.name}'));
  channel.events.listen((e) {
    received.add(e);
    print(
      '[${_hora()}] evento ${e.event}: ${e.payload['id']} '
      '(${e.payload['tipo']}, ${e.payload['lat']}, ${e.payload['lng']})',
    );
  });

  channel.connect();

  if (watch) {
    print('Escuchando en ${realtimeUrl(api)} (Ctrl+C para salir)');
    await Completer<void>().future;
  }

  await channel.statuses
      .firstWhere((s) => s == RealtimeStatus.connected)
      .timeout(const Duration(seconds: 10));

  final marca = 'smoke:${const Uuid().v4().substring(0, 8)}';
  final id = await _crearReporte(api, marca);
  print('[${_hora()}] POST /v1/incidents -> $id ($marca)');

  await Future<void>.delayed(const Duration(seconds: 2));
  channel.dispose();

  final llego = received.any((e) => e.payload['id'] == id);
  print(
    llego
        ? 'OK: el evento incidente_nuevo llegó por el WebSocket'
        : 'FALLO: el reporte se creó pero no llegó el evento',
  );
  exit(llego ? 0 : 1);
}

Future<String> _crearReporte(String api, String marca) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(Uri.parse('$api/v1/incidents'));
    request.headers
      ..contentType = ContentType.json
      ..set('idempotency-key', const Uuid().v4());
    request.write(
      jsonEncode({
        'tipo': 'otro',
        'descripcion': marca,
        'lat': -16.4,
        'lng': -71.5,
      }),
    );
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode != 201) {
      throw StateError('POST falló: ${response.statusCode} $body');
    }
    return (jsonDecode(body) as Map)['data']['id'] as String;
  } finally {
    client.close();
  }
}

String _hora() => DateTime.now().toIso8601String().substring(11, 19);
