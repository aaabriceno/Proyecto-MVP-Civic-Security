import 'package:civic_security/core/config/env.dart';
import 'package:civic_security/core/config/server_address.dart';
import 'package:civic_security/core/network/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalizeServerAddress', () {
    test('una IP sola: http y el puerto 4000 del servidor de desarrollo', () {
      expect(
        normalizeServerAddress('172.20.10.14'),
        'http://172.20.10.14:4000',
      );
    });

    test('IP y puerto, sin esquema', () {
      expect(
        normalizeServerAddress('192.168.1.7:4000'),
        'http://192.168.1.7:4000',
      );
      expect(
        normalizeServerAddress('192.168.1.7:5000'),
        'http://192.168.1.7:5000',
      );
    });

    test('con esquema se respeta tal cual', () {
      expect(
        normalizeServerAddress('http://10.0.2.2:4000'),
        'http://10.0.2.2:4000',
      );
      expect(
        normalizeServerAddress('https://civic.example.com'),
        'https://civic.example.com',
      );
    });

    test('ignora espacios y una barra final', () {
      expect(
        normalizeServerAddress('  http://172.20.10.14:4000/  '),
        'http://172.20.10.14:4000',
      );
    });

    test('un nombre de equipo también vale', () {
      expect(
        normalizeServerAddress('mi-laptop.local'),
        'http://mi-laptop.local:4000',
      );
    });

    test('lo que no es una dirección se rechaza', () {
      for (final malo in [
        '',
        '   ',
        'hola mundo',
        'ftp://172.20.10.14',
        'http://',
        'http://172.20.10.14:4000/v1',
        'http://172.20.10.14:4000?x=1',
        'http://usuario:clave@172.20.10.14',
        '172.20.10.14:abc',
        '172.20.10.14:99999',
        '172.20.10.14:0',
        '[::1]:4000',
        'http://172.20.10.14:4000#frag',
        'javascript:alert(1)',
      ]) {
        expect(normalizeServerAddress(malo), isNull, reason: '"$malo"');
      }
    });
  });

  group('serverUrlProvider', () {
    test('por omisión es la dirección con la que se compiló la app', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(serverUrlProvider), apiUrl);
    });

    test('el cliente HTTP habla con la dirección elegida', () {
      final container = ProviderContainer(
        overrides: [
          serverUrlProvider.overrideWithValue('http://172.20.10.14:4000'),
        ],
      );
      addTearDown(container.dispose);

      expect(
        container.read(dioProvider).options.baseUrl,
        'http://172.20.10.14:4000',
      );
    });
  });

  test(
    'la versión final sigue exigiendo https, elija la dirección que elija',
    () {
      expect(
        () => validateApiUrl('http://172.20.10.14:4000', release: true),
        throwsStateError,
      );
    },
  );
}
