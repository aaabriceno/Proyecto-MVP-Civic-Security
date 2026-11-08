import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_failure.dart';
import '../../../core/storage/token_store.dart';
import '../domain/auth_models.dart';
import 'auth_repository.dart';

/// Guarda y renueva la sesión: el access token en memoria y el refresh token en
/// el almacén seguro. Es de quien se fían el resto de la app y el futuro cliente
/// HTTP para saber con qué token hablar con el servidor.
///
/// Reglas que cumple:
///
///  * El refresh token nuevo se guarda **antes** de entregar el access token: el
///    servidor da el viejo por perdido en cuanto lo rota.
///  * Una sola renovación a la vez. Si varias partes de la app la piden al mismo
///    tiempo comparten una petición; con dos, la segunda llevaría un token ya
///    usado y el servidor lo tomaría por un robo.
///  * Solo `invalid_token` termina la sesión. Un fallo de red, un 429 o un 503
///    se relanzan y la sesión se conserva para reintentar.
///  * Cerrar sesión siempre borra lo local, aunque el servidor no responda.
class SessionManager {
  SessionManager({
    required this._repository,
    required this._store,
    this._now = DateTime.now,
  });

  /// Se renueva un poco antes de que venza para no mandar un token que
  /// caduca en el camino.
  static const _margin = Duration(seconds: 30);

  final AuthRepository _repository;
  final TokenStore _store;
  final DateTime Function() _now;

  String? _accessToken;
  DateTime? _accessExpiresAt;
  Future<String?>? _refreshing;

  /// Inicia la sesión con los tokens de un registro o un inicio de sesión.
  Future<void> start(AuthTokens tokens) async {
    await _store.saveRefreshToken(tokens.refreshToken);
    _remember(tokens);
  }

  /// El access token si sigue vigente; si no, lo renueva. `null` significa que
  /// no hay sesión. Lanza [ApiFailure] si la renovación falla por red o servidor.
  Future<String?> validAccessToken() {
    final token = _accessToken;
    final expiresAt = _accessExpiresAt;
    if (token != null &&
        expiresAt != null &&
        _now().isBefore(expiresAt.subtract(_margin))) {
      return Future.value(token);
    }
    return refresh();
  }

  /// Renueva el access token con el refresh token guardado, aunque el actual
  /// siga vigente (p. ej. si el servidor lo rechazó). Devuelve el nuevo, o
  /// `null` si no hay sesión o el servidor la dio por terminada.
  Future<String?> refresh() {
    // `whenComplete` libera el candado tanto si sale bien como si falla
    return _refreshing ??= _renew().whenComplete(() => _refreshing = null);
  }

  /// Cierra la sesión. Lo local se borra siempre; revocar en el servidor es un
  /// esfuerzo extra que no hace falta que salga bien.
  Future<void> end() async {
    // Si hay una renovación en curso, se espera: así no puede terminar después
    // y volver a guardar un token en una sesión ya cerrada.
    try {
      await _refreshing;
    } on Object {
      // Su error no importa: la sesión se cierra de todos modos
    }

    final token = await _store.readRefreshToken();
    _forget();
    await _store.clear();

    if (token == null) return;
    try {
      await _repository.logout(token);
    } on ApiFailure {
      // Sin red o con el servidor ocupado: el refresh token vencerá solo
    }
  }

  Future<String?> _renew() async {
    final stored = await _store.readRefreshToken();
    if (stored == null) return null;

    final AuthTokens tokens;
    try {
      tokens = await _repository.refresh(stored);
    } on ApiFailure catch (failure) {
      if (failure.code != 'invalid_token') rethrow;
      // El servidor ya no reconoce esta sesión: usada, revocada o vencida
      _forget();
      await _store.clear();
      return null;
    }

    // Primero a salvo en disco, después a disposición del resto de la app
    await _store.saveRefreshToken(tokens.refreshToken);
    _remember(tokens);
    return tokens.accessToken;
  }

  void _remember(AuthTokens tokens) {
    _accessToken = tokens.accessToken;
    _accessExpiresAt = _now().add(tokens.expiresIn);
  }

  void _forget() {
    _accessToken = null;
    _accessExpiresAt = null;
  }
}

/// Una sola sesión para toda la app.
final sessionManagerProvider = Provider<SessionManager>(
  (ref) => SessionManager(
    repository: ref.watch(authRepositoryProvider),
    store: ref.watch(tokenStoreProvider),
  ),
);
