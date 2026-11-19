import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/env.dart';
import '../config/server_address.dart';

/// En una build de producción la API debe usar https: con http cualquiera en
/// la misma red podría leer o alterar los reportes. Falla al arrancar en lugar
/// de funcionar inseguro sin que nadie lo note.
void validateApiUrl(String url, {required bool release}) {
  if (release && !url.startsWith('https://')) {
    throw StateError(
      'API_URL debe usar https en builds de producción (recibido: $url)',
    );
  }
}

/// Un cliente HTTP nuevo hacia la API. Lo usan [dioProvider] y el cliente con
/// sesión (`sessionDioProvider`). [baseUrl] es el servidor elegido (por omisión
/// el de compilación).
Dio newApiClient({String? baseUrl}) {
  final url = baseUrl ?? apiUrl;
  validateApiUrl(url, release: kReleaseMode);
  return Dio(
    BaseOptions(
      baseUrl: url,
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 10),
      headers: {'accept': 'application/json'},
    ),
  );
}

/// Cliente sin sesión: el registro, el inicio de sesión y todo lo público.
final dioProvider = Provider<Dio>(
  (ref) => newApiClient(baseUrl: ref.watch(serverUrlProvider)),
);
