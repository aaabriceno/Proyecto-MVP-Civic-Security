import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/auth_interceptor.dart';
import 'session_manager.dart';

/// Cliente HTTP que sabe hablar con la sesión del usuario: las peticiones
/// marcadas con `conSesion()` llevan su access token y, si el servidor lo
/// rechaza, renuevan la sesión y se repiten una vez. Las demás pasan sin tocarse.
///
/// Es distinto de [dioProvider] a propósito: el cliente de las cuentas no puede
/// depender de la sesión, porque es el que la renueva.
final sessionDioProvider = Provider<Dio>((ref) {
  final dio = newApiClient();
  final session = ref.watch(sessionManagerProvider);
  dio.interceptors.add(
    AuthInterceptor(
      dio: dio,
      accessToken: session.validAccessToken,
      refresh: session.refresh,
    ),
  );
  return dio;
});
