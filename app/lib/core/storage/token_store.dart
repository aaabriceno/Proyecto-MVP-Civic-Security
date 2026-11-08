import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Dónde se guarda el refresh token entre una apertura de la app y la
/// siguiente. Es una interfaz para poder reemplazarla por un falso en los tests.
///
/// Solo se guarda el refresh token. El access token dura 15 minutos y vive solo
/// en memoria: nunca se escribe en disco.
abstract interface class TokenStore {
  /// El refresh token guardado, o `null` si no hay sesión.
  Future<String?> readRefreshToken();

  Future<void> saveRefreshToken(String token);

  /// Borra la sesión guardada. No falla si no había nada.
  Future<void> clear();
}

/// Guarda el token cifrado con una clave que vive en el Keystore de Android,
/// no en un archivo común. La copia de seguridad de la app está desactivada
/// (`android:allowBackup="false"`), así que el token no sale del teléfono.
class SecureTokenStore implements TokenStore {
  SecureTokenStore([
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  ]) : _storage = storage;

  static const _key = 'civic.refresh_token';

  final FlutterSecureStorage _storage;

  @override
  Future<String?> readRefreshToken() async {
    final value = await _storage.read(key: _key);
    return value == null || value.isEmpty ? null : value;
  }

  @override
  Future<void> saveRefreshToken(String token) =>
      _storage.write(key: _key, value: token);

  @override
  Future<void> clear() => _storage.delete(key: _key);
}

final tokenStoreProvider = Provider<TokenStore>((ref) => SecureTokenStore());
