import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_failure.dart';
import '../domain/auth_models.dart';

/// Habla con los endpoints de cuentas. Es una interfaz para poder reemplazarla
/// por un falso en los tests. Todo fallo se lanza como [ApiFailure].
abstract interface class AuthRepository {
  /// Crea la cuenta y deja la sesión iniciada.
  Future<AuthSession> register({
    required String alias,
    required String password,
    required bool acceptsConsent,
  });

  Future<AuthSession> login({required String alias, required String password});

  /// Cambia un refresh token por un par nuevo. El servidor da el token usado
  /// por perdido: hay que guardar el nuevo antes de hacer nada más.
  Future<AuthTokens> refresh(String refreshToken);

  /// Cierra la sesión en el servidor (revoca el refresh token).
  Future<void> logout(String refreshToken);

  /// La cuenta de quien tiene este access token.
  Future<AuthUser> me(String accessToken);
}

class HttpAuthRepository implements AuthRepository {
  HttpAuthRepository(this._dio);

  final Dio _dio;

  @override
  Future<AuthSession> register({
    required String alias,
    required String password,
    required bool acceptsConsent,
  }) => _session('/v1/auth/register', {
    'alias': alias,
    'password': password,
    'acepta_consentimiento': acceptsConsent,
  });

  @override
  Future<AuthSession> login({
    required String alias,
    required String password,
  }) => _session('/v1/auth/login', {'alias': alias, 'password': password});

  @override
  Future<AuthTokens> refresh(String refreshToken) => _guard(() async {
    final response = await _dio.post<Object?>(
      '/v1/auth/refresh',
      data: {'refresh_token': refreshToken},
    );
    final tokens = _data(response.data) == null
        ? null
        : AuthTokens.tryFromJson(_data(response.data)!);
    if (tokens == null) throw const ApiFailure.invalidResponse();
    return tokens;
  });

  @override
  Future<void> logout(String refreshToken) => _guard(() async {
    await _dio.post<Object?>(
      '/v1/auth/logout',
      data: {'refresh_token': refreshToken},
    );
  });

  @override
  Future<AuthUser> me(String accessToken) => _guard(() async {
    final response = await _dio.get<Object?>(
      '/v1/me',
      options: Options(headers: {'authorization': 'Bearer $accessToken'}),
    );
    final user = _data(response.data) == null
        ? null
        : AuthUser.tryFromJson(_data(response.data)!);
    if (user == null) throw const ApiFailure.invalidResponse();
    return user;
  });

  Future<AuthSession> _session(String path, Map<String, Object> body) =>
      _guard(() async {
        final response = await _dio.post<Object?>(path, data: body);
        final data = _data(response.data);
        final session = data == null ? null : AuthSession.tryFromJson(data);
        if (session == null) throw const ApiFailure.invalidResponse();
        return session;
      });

  /// El contenido de `{"data": {...}}`, o `null` si la respuesta no tiene esa forma.
  Map<String, dynamic>? _data(Object? body) {
    if (body is! Map) return null;
    final data = body['data'];
    return data is Map<String, dynamic> ? data : null;
  }

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      throw ApiFailure.fromDio(e);
    } on FormatException {
      throw const ApiFailure.invalidResponse();
    }
  }
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => HttpAuthRepository(ref.watch(dioProvider)),
);
