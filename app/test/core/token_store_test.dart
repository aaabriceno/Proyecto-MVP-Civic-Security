import 'package:civic_security/core/storage/token_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // El almacenamiento seguro real usa el Keystore de Android; en los tests se
  // reemplaza por uno en memoria que se comporta igual de cara al código.
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  group('SecureTokenStore', () {
    test('sin nada guardado devuelve null', () async {
      expect(await SecureTokenStore().readRefreshToken(), isNull);
    });

    test('guarda el refresh token y lo devuelve', () async {
      final store = SecureTokenStore();

      await store.saveRefreshToken('refresh-1');

      expect(await store.readRefreshToken(), 'refresh-1');
    });

    test(
      'guardar otro lo reemplaza (el servidor rota el token en cada uso)',
      () async {
        final store = SecureTokenStore();

        await store.saveRefreshToken('refresh-1');
        await store.saveRefreshToken('refresh-2');

        expect(await store.readRefreshToken(), 'refresh-2');
      },
    );

    test('clear lo borra', () async {
      final store = SecureTokenStore();
      await store.saveRefreshToken('refresh-1');

      await store.clear();

      expect(await store.readRefreshToken(), isNull);
    });

    test('clear sin nada guardado no falla', () async {
      await SecureTokenStore().clear();
    });

    test(
      'lo guardado sobrevive a una instancia nueva (como reiniciar la app)',
      () async {
        await SecureTokenStore().saveRefreshToken('refresh-1');

        expect(await SecureTokenStore().readRefreshToken(), 'refresh-1');
      },
    );

    test('un valor vacío cuenta como "no hay token"', () async {
      final store = SecureTokenStore();

      await store.saveRefreshToken('');

      expect(await store.readRefreshToken(), isNull);
    });
  });
}
