import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/env.dart';

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

final dioProvider = Provider<Dio>((ref) {
  validateApiUrl(apiUrl, release: kReleaseMode);
  return Dio(
    BaseOptions(
      baseUrl: apiUrl,
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 10),
      headers: {'accept': 'application/json'},
    ),
  );
});
