import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'env.dart';

/// El puerto del servidor de desarrollo: se usa cuando la persona escribe solo
/// la IP (`172.20.10.14`).
const _defaultPort = 4000;

final _hostPattern = RegExp(r'^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$');

/// Convierte lo que escribe una persona en la dirección del servidor, o `null`
/// si no es una dirección válida:
///
///  * `172.20.10.14` → `http://172.20.10.14:4000` (solo la IP: http y puerto 4000)
///  * `172.20.10.14:5000` → `http://172.20.10.14:5000`
///  * `https://civic.example.com` → se respeta tal cual
///
/// Solo acepta `http`/`https`, un equipo (IP o nombre) y, si se quiere, un
/// puerto. Rechaza rutas, parámetros, usuario y clave: una dirección de
/// servidor no lleva nada de eso, y así no se cuela otra cosa en la `baseUrl`.
String? normalizeServerAddress(String input) {
  final text = input.trim();
  if (text.isEmpty) return null;

  final hasScheme = text.contains('://');
  final uri = Uri.tryParse(hasScheme ? text : 'http://$text');
  if (uri == null) return null;

  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  if (uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) return null;
  if (uri.path.isNotEmpty && uri.path != '/') return null;
  if (!_hostPattern.hasMatch(uri.host)) return null;

  final int? port;
  if (uri.hasPort) {
    if (uri.port < 1 || uri.port > 65535) return null;
    port = uri.port;
  } else {
    // Sin esquema y sin puerto: se entiende que es el servidor de desarrollo
    port = hasScheme ? null : _defaultPort;
  }
  return '${uri.scheme}://${uri.host}${port == null ? '' : ':$port'}';
}

/// A qué servidor habla la app. Por omisión, el de `API_URL` (al compilar); en
/// las versiones de prueba se puede cambiar desde la pantalla de bienvenida
/// (ver `ServerAddressLink`).
final serverUrlProvider = Provider<String>((ref) => apiUrl);

/// Dónde se guarda la dirección elegida entre una apertura de la app y la
/// siguiente. Es una interfaz para poder reemplazarla por un falso en los tests.
abstract interface class ServerAddressStore {
  Future<String?> read();

  Future<void> save(String url);

  /// Vuelve a la dirección de compilación. No falla si no había nada.
  Future<void> clear();
}

class SecureServerAddressStore implements ServerAddressStore {
  SecureServerAddressStore([
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  ]) : _storage = storage;

  static const _key = 'civic.server_url';

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() async {
    final value = await _storage.read(key: _key);
    // Lo guardado se vuelve a validar: nunca se confía en lo que hay en disco
    return value == null ? null : normalizeServerAddress(value);
  }

  @override
  Future<void> save(String url) => _storage.write(key: _key, value: url);

  @override
  Future<void> clear() => _storage.delete(key: _key);
}

final serverAddressStoreProvider = Provider<ServerAddressStore>(
  (ref) => SecureServerAddressStore(),
);

/// ¿Responde un servidor en [baseUrl]? Es una función para poder reemplazarla
/// en los tests.
typedef ServerHealthCheck = Future<bool> Function(String baseUrl);

final serverHealthCheckProvider = Provider<ServerHealthCheck>(
  (ref) => (baseUrl) async {
    try {
      final dio = Dio(
        BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 4),
          receiveTimeout: const Duration(seconds: 4),
        ),
      );
      final response = await dio.get<Object?>('/health');
      final body = response.data;
      return response.statusCode == 200 &&
          body is Map &&
          body['status'] == 'ok';
    } on Object {
      return false;
    }
  },
);

/// La dirección que se eligió en una apertura anterior, para arrancar con ella.
///
/// Solo en las versiones de prueba: la versión final ([release]) siempre usa la
/// de compilación (https) y ni siquiera lee lo guardado. Si el almacén falla,
/// también se usa la de compilación.
Future<String?> loadSavedServer(
  ServerAddressStore store, {
  required bool release,
}) async {
  if (release) return null;
  try {
    return await store.read();
  } on Object {
    return null;
  }
}
