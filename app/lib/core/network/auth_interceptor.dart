import 'package:dio/dio.dart';

import 'api_failure.dart';

const _necesitaSesion = 'necesita_sesion';
const _yaReintentada = 'sesion_reintentada';

/// Marca una petición como "necesita sesión": [AuthInterceptor] le agrega el
/// access token y, si el servidor la rechaza con 401, renueva la sesión y la
/// repite. Las peticiones sin esta marca (el mapa de solo lectura, el registro,
/// el inicio de sesión) no se tocan.
Options conSesion([Options? options]) => (options ?? Options()).copyWith(
  extra: {...?options?.extra, _necesitaSesion: true},
);

/// Adjunta la sesión a las peticiones marcadas con [conSesion].
///
///  * Antes de enviar pide un access token vigente (renovándolo si hace falta).
///    Sin sesión, la petición **no sale** y falla con `unauthorized`.
///  * Si aun así el servidor responde 401, renueva y repite **una sola vez**:
///    más de una vuelta sería un ciclo si el problema no es el token.
///
/// Recibe funciones y no el administrador de sesión para que esta capa no
/// dependa de las funciones de la app. Un `401` de una petición pública no
/// dispara ninguna renovación.
class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required this._dio,
    required this._accessToken,
    required this._refresh,
  });

  final Dio _dio;
  final Future<String?> Function() _accessToken;
  final Future<String?> Function() _refresh;

  static const _sinSesion = ApiFailure(
    code: 'unauthorized',
    message: 'Necesitas iniciar sesión',
  );

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (options.extra[_necesitaSesion] != true) return handler.next(options);

    try {
      final token = await _accessToken();
      if (token == null) return _rechazar(handler, options, _sinSesion);

      options.headers['authorization'] = 'Bearer $token';
      handler.next(options);
    } on ApiFailure catch (failure) {
      // Sin red o con el servidor ocupado al renovar: se avisa tal cual
      _rechazar(handler, options, failure);
    }
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final options = err.requestOptions;
    final renovable =
        err.response?.statusCode == 401 &&
        options.extra[_necesitaSesion] == true &&
        options.extra[_yaReintentada] != true;
    if (!renovable) return handler.next(err);

    final String? nuevo;
    try {
      nuevo = await _refresh();
    } on ApiFailure catch (failure) {
      return handler.next(
        DioException(requestOptions: options, error: failure),
      );
    }
    // La sesión terminó: el 401 del servidor llega tal cual a quien llamó
    if (nuevo == null) return handler.next(err);

    options.extra[_yaReintentada] = true;
    options.headers['authorization'] = 'Bearer $nuevo';
    try {
      handler.resolve(await _dio.fetch<Object?>(options));
    } on DioException catch (e) {
      handler.next(e);
    }
  }

  void _rechazar(
    RequestInterceptorHandler handler,
    RequestOptions options,
    ApiFailure failure,
  ) => handler.reject(
    DioException(requestOptions: options, error: failure),
    // No pasa por onError: no hay respuesta que reintentar
    false,
  );
}
