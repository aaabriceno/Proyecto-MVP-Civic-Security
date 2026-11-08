import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_failure.dart';
import '../data/auth_repository.dart';
import '../data/session_manager.dart';
import '../domain/auth_models.dart';

/// En qué punto está la sesión de la persona.
enum AuthStatus {
  /// Abriendo la app: todavía se está recuperando la sesión guardada.
  loading,

  /// No hay sesión.
  signedOut,

  /// Hay sesión y el servidor la confirmó.
  signedIn,

  /// Hay una sesión guardada pero no hubo señal para confirmarla. La app deja
  /// entrar y se reintenta; no se cierra la sesión por falta de red.
  offline,
}

/// Estado de la sesión más lo que necesitan los formularios de entrar y
/// registrarse: si hay una petición en curso y cuál fue el último error.
class AuthState {
  const AuthState._(this.status, {this.user, this.busy = false, this.failure});

  const AuthState.loading() : this._(AuthStatus.loading);

  const AuthState.signedOut({bool busy = false, ApiFailure? failure})
    : this._(AuthStatus.signedOut, busy: busy, failure: failure);

  const AuthState.signedIn(AuthUser user)
    : this._(AuthStatus.signedIn, user: user);

  const AuthState.offline() : this._(AuthStatus.offline);

  final AuthStatus status;

  /// La cuenta; solo cuando [status] es [AuthStatus.signedIn].
  final AuthUser? user;

  /// Hay un registro o un inicio de sesión en curso.
  final bool busy;

  /// El error del último intento, para mostrarlo en el formulario.
  final ApiFailure? failure;
}

/// Decide si la persona tiene sesión y hace entrar, registrarse y salir.
///
/// Vive toda la app. Quien muestre la primera pantalla debe llamar a [restore]
/// una vez: el estado arranca en [AuthStatus.loading] hasta entonces.
class AuthController extends Notifier<AuthState> {
  Future<void>? _restoring;

  SessionManager get _session => ref.read(sessionManagerProvider);
  AuthRepository get _repository => ref.read(authRepositoryProvider);

  @override
  AuthState build() => const AuthState.loading();

  /// Recupera la sesión guardada. Se puede volver a llamar (p. ej. al volver la
  /// señal) y varias llamadas a la vez comparten una sola ronda.
  Future<void> restore() =>
      _restoring ??= _restore().whenComplete(() => _restoring = null);

  Future<void> _restore() async {
    try {
      final access = await _session.validAccessToken();
      if (access == null) {
        _set(const AuthState.signedOut());
        return;
      }
      final user = await _repository.me(access);
      _set(AuthState.signedIn(user));
    } on ApiFailure catch (failure) {
      if (failure.code == 'unauthorized' || failure.code == 'invalid_token') {
        // El servidor no acepta ni el token recién emitido: no hay sesión
        await _end();
        _set(const AuthState.signedOut());
      } else {
        // Sin red, servidor ocupado, etc.: la sesión sigue guardada
        _set(const AuthState.offline());
      }
    } on Object {
      _set(const AuthState.signedOut(failure: ApiFailure.unexpected()));
    }
  }

  Future<void> register({
    required String alias,
    required String password,
    required bool acceptsConsent,
  }) => _authenticate(
    () => _repository.register(
      alias: alias,
      password: password,
      acceptsConsent: acceptsConsent,
    ),
  );

  Future<void> login({required String alias, required String password}) =>
      _authenticate(() => _repository.login(alias: alias, password: password));

  Future<void> _authenticate(Future<AuthSession> Function() call) async {
    // Un doble toque, o entrar teniendo ya sesión, no hace nada
    if (state.busy || state.status == AuthStatus.signedIn) return;

    state = const AuthState.signedOut(busy: true);
    try {
      final session = await call();
      await _session.start(session.tokens);
      _set(AuthState.signedIn(session.user));
    } on ApiFailure catch (failure) {
      _set(AuthState.signedOut(failure: failure));
    } on Object {
      _set(const AuthState.signedOut(failure: ApiFailure.unexpected()));
    }
  }

  /// Cierra la sesión. La persona queda fuera al instante; revocar en el
  /// servidor se hace después y no hace falta esperarlo.
  Future<void> logout() async {
    state = const AuthState.signedOut();
    try {
      await _session.end();
    } on Object {
      _set(const AuthState.signedOut(failure: ApiFailure.unexpected()));
    }
  }

  /// Quita el error de la pantalla, p. ej. al cambiar de formulario.
  void clearFailure() {
    if (state.failure == null) return;
    state = AuthState.signedOut(busy: state.busy);
  }

  Future<void> _end() async {
    try {
      await _session.end();
    } on Object {
      // Se intenta; si falla, el estado ya refleja que no hay sesión
    }
  }

  // Tras un `await` la pantalla pudo cerrarse: no se toca un estado muerto
  void _set(AuthState next) {
    if (ref.mounted) state = next;
  }
}

final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);
