import 'dart:async';

import 'package:civic_security/core/storage/token_store.dart';
import 'package:civic_security/features/auth/data/auth_repository.dart';
import 'package:civic_security/features/auth/domain/auth_models.dart';

/// Un par de tokens de prueba. El access token dura 15 minutos, como en la API.
AuthTokens tokens(String access, String refresh) => AuthTokens(
  accessToken: access,
  refreshToken: refresh,
  expiresIn: const Duration(minutes: 15),
);

/// Almacén en memoria que anota cada escritura y puede retener una para probar
/// el orden de las operaciones.
class InMemoryTokenStore implements TokenStore {
  InMemoryTokenStore([this.value]);

  /// Lo que hay guardado ahora mismo.
  String? value;

  /// Lo que se fue haciendo, en orden: `save:<token>` y `clear`.
  final events = <String>[];

  /// Si se asigna, `saveRefreshToken` espera a que se complete antes de guardar.
  Completer<void>? saveGate;

  @override
  Future<String?> readRefreshToken() async => value;

  @override
  Future<void> saveRefreshToken(String token) async {
    events.add('save:$token');
    final gate = saveGate;
    if (gate != null) await gate.future;
    value = token;
  }

  @override
  Future<void> clear() async {
    events.add('clear');
    value = null;
  }
}

/// Repositorio de cuentas que responde lo que cada test le indique. Un método
/// sin respuesta configurada falla, para detectar llamadas inesperadas.
class FakeAuthRepository implements AuthRepository {
  Future<AuthSession> Function(String alias, String password, bool consent)?
  onRegister;
  Future<AuthSession> Function(String alias, String password)? onLogin;
  Future<AuthTokens> Function(String refreshToken)? onRefresh;
  Future<void> Function(String refreshToken)? onLogout;
  Future<AuthUser> Function(String accessToken)? onMe;

  final registerCalls = <String>[];
  final loginCalls = <String>[];
  final refreshCalls = <String>[];
  final logoutCalls = <String>[];
  final meCalls = <String>[];

  @override
  Future<AuthSession> register({
    required String alias,
    required String password,
    required bool acceptsConsent,
  }) {
    registerCalls.add(alias);
    return _handler(onRegister, 'register')(alias, password, acceptsConsent);
  }

  @override
  Future<AuthSession> login({required String alias, required String password}) {
    loginCalls.add(alias);
    return _handler(onLogin, 'login')(alias, password);
  }

  @override
  Future<AuthTokens> refresh(String refreshToken) {
    refreshCalls.add(refreshToken);
    return _handler(onRefresh, 'refresh')(refreshToken);
  }

  @override
  Future<void> logout(String refreshToken) {
    logoutCalls.add(refreshToken);
    return _handler(onLogout, 'logout')(refreshToken);
  }

  @override
  Future<AuthUser> me(String accessToken) {
    meCalls.add(accessToken);
    return _handler(onMe, 'me')(accessToken);
  }

  T _handler<T>(T? handler, String name) =>
      handler ?? (throw StateError('Llamada inesperada a $name()'));
}
