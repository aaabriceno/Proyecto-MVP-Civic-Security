/// Nivel de una cuenta. [wire] es el valor que usa la API.
enum AuthLevel {
  /// Cuenta creada pero sin verificar el DNI.
  invitado('invitado'),

  /// DNI verificado: puede reportar y votar con todo su peso.
  verificado('verificado');

  const AuthLevel(this.wire);

  final String wire;

  /// `null` si el servidor envía un nivel que esta versión no conoce.
  static AuthLevel? fromWire(String? value) {
    for (final level in values) {
      if (level.wire == value) return level;
    }
    return null;
  }
}

/// Cuántos reportes nuevos lleva la cuenta hoy y cuántos le corresponden.
class ReportQuota {
  const ReportQuota({required this.usados, required this.maximo});

  /// `null` si no tiene la forma esperada.
  static ReportQuota? tryFromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final usados = json['usados'];
    final maximo = json['maximo'];
    if (usados is! int || usados < 0) return null;
    if (maximo is! int || maximo <= 0) return null;
    return ReportQuota(usados: usados, maximo: maximo);
  }

  final int usados;
  final int maximo;

  /// Los que quedan hoy; nunca negativo.
  int get restantes => (maximo - usados).clamp(0, maximo);
}

/// La cuenta, tal como la expone la API: id, alias y nivel. El perfil (`/me`)
/// agrega desde cuándo existe y el cupo del día; en un registro o un inicio de
/// sesión esos dos vienen vacíos.
class AuthUser {
  const AuthUser({
    required this.id,
    required this.alias,
    required this.nivel,
    this.desde,
    this.cupo,
  });

  /// Devuelve `null` si falta algún campo, tiene otro tipo o el nivel no se
  /// conoce (un servidor más nuevo que la app). Nunca lanza. Un `desde` o un
  /// `cupo` malformado se ignora: no invalida la cuenta.
  static AuthUser? tryFromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final alias = json['alias'];
    final nivel = json['nivel'];
    if (id is! String || id.isEmpty) return null;
    if (alias is! String || alias.isEmpty) return null;
    final level = nivel is String ? AuthLevel.fromWire(nivel) : null;
    if (level == null) return null;
    return AuthUser(
      id: id,
      alias: alias,
      nivel: level,
      desde: _parseMonth(json['desde']),
      cupo: ReportQuota.tryFromJson(json['cupo']),
    );
  }

  // "2026-09" -> septiembre de 2026
  static DateTime? _parseMonth(Object? raw) {
    if (raw is! String) return null;
    final match = RegExp(r'^(\d{4})-(0[1-9]|1[0-2])$').firstMatch(raw);
    if (match == null) return null;
    return DateTime(int.parse(match[1]!), int.parse(match[2]!));
  }

  final String id;
  final String alias;
  final AuthLevel nivel;

  /// El mes en que se creó la cuenta (solo año y mes), si se sabe.
  final DateTime? desde;

  /// Cuánto lleva del cupo diario de reportes, si se sabe.
  final ReportQuota? cupo;
}

/// El par de tokens de una sesión.
///
/// El access token dura poco y vive solo en memoria. El refresh token es el que
/// se guarda en el almacenamiento seguro y el servidor lo cambia en cada uso.
class AuthTokens {
  const AuthTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
  });

  /// Devuelve `null` si falta algún campo, viene vacío o tiene otro tipo.
  static AuthTokens? tryFromJson(Map<String, dynamic> json) {
    final access = json['access_token'];
    final refresh = json['refresh_token'];
    final expiresIn = json['expires_in'];
    if (access is! String || access.isEmpty) return null;
    if (refresh is! String || refresh.isEmpty) return null;
    if (expiresIn is! int || expiresIn <= 0) return null;
    return AuthTokens(
      accessToken: access,
      refreshToken: refresh,
      expiresIn: Duration(seconds: expiresIn),
    );
  }

  final String accessToken;
  final String refreshToken;

  /// Cuánto dura el access token desde que se emitió.
  final Duration expiresIn;

  // Un token no debe poder acabar en un log por un print o una excepción.
  @override
  String toString() => 'AuthTokens(***)';
}

/// La respuesta de un registro o un inicio de sesión: la cuenta y sus tokens.
class AuthSession {
  const AuthSession({required this.user, required this.tokens});

  static AuthSession? tryFromJson(Map<String, dynamic> json) {
    final rawUser = json['user'];
    if (rawUser is! Map<String, dynamic>) return null;
    final user = AuthUser.tryFromJson(rawUser);
    final tokens = AuthTokens.tryFromJson(json);
    if (user == null || tokens == null) return null;
    return AuthSession(user: user, tokens: tokens);
  }

  final AuthUser user;
  final AuthTokens tokens;
}
