import 'dart:async';

import 'package:civic_security/core/network/api_failure.dart';
import 'package:civic_security/features/auth/data/session_manager.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

const _tokenInvalido = ApiFailure(
  code: 'invalid_token',
  message: 'Sesión inválida o vencida',
);

void main() {
  late InMemoryTokenStore store;
  late FakeAuthRepository repo;
  late DateTime clock;
  late SessionManager session;

  SessionManager newManager() =>
      SessionManager(repository: repo, store: store, now: () => clock);

  setUp(() {
    store = InMemoryTokenStore();
    repo = FakeAuthRepository();
    clock = DateTime.utc(2026, 11, 8, 12);
    session = newManager();
  });

  group('start (después de entrar o registrarse)', () {
    test('guarda el refresh token y deja el access token en memoria', () async {
      await session.start(tokens('access-1', 'refresh-1'));

      expect(store.value, 'refresh-1');
      expect(await session.validAccessToken(), 'access-1');
      expect(repo.refreshCalls, isEmpty);
    });

    test('el access token nunca se escribe en el almacén', () async {
      await session.start(tokens('access-1', 'refresh-1'));

      expect(store.events, ['save:refresh-1']);
    });
  });

  group('validAccessToken', () {
    test('sin sesión guardada devuelve null y no llama al servidor', () async {
      expect(await session.validAccessToken(), isNull);
      expect(repo.refreshCalls, isEmpty);
    });

    test('con el access token vigente no llama al servidor', () async {
      await session.start(tokens('access-1', 'refresh-1'));

      clock = clock.add(const Duration(minutes: 14, seconds: 29));

      expect(await session.validAccessToken(), 'access-1');
      expect(repo.refreshCalls, isEmpty);
    });

    test('a menos de 30 segundos de vencer ya lo renueva', () async {
      await session.start(tokens('access-1', 'refresh-1'));
      repo.onRefresh = (_) async => tokens('access-2', 'refresh-2');

      clock = clock.add(const Duration(minutes: 14, seconds: 31));

      expect(await session.validAccessToken(), 'access-2');
      expect(repo.refreshCalls, ['refresh-1']);
    });

    test(
      'al reabrir la app (nada en memoria) renueva con el refresh guardado',
      () async {
        store.value = 'refresh-1';
        repo.onRefresh = (_) async => tokens('access-2', 'refresh-2');

        expect(await session.validAccessToken(), 'access-2');
        expect(repo.refreshCalls, ['refresh-1']);
        expect(store.value, 'refresh-2');
      },
    );
  });

  group('refresh', () {
    test(
      'sin refresh token guardado devuelve null y no llama al servidor',
      () async {
        expect(await session.refresh(), isNull);
        expect(repo.refreshCalls, isEmpty);
      },
    );

    test('guarda el refresh nuevo ANTES de entregar el access token', () async {
      store.value = 'refresh-1';
      repo.onRefresh = (_) async => tokens('access-2', 'refresh-2');
      store.saveGate = Completer<void>();

      String? result;
      var done = false;
      unawaited(
        session.refresh().then((value) {
          result = value;
          done = true;
        }),
      );
      await Future<void>.delayed(Duration.zero);

      // El servidor ya rotó el token, pero aún no se guardó el nuevo: no se
      // entrega nada hasta que quede a salvo
      expect(done, isFalse);
      expect(store.events, ['save:refresh-2']);

      store.saveGate!.complete();
      await Future<void>.delayed(Duration.zero);

      expect(done, isTrue);
      expect(result, 'access-2');
      expect(store.value, 'refresh-2');
    });

    test('varias peticiones a la vez comparten UNA sola renovación', () async {
      store.value = 'refresh-1';
      final gate = Completer<void>();
      repo.onRefresh = (_) async {
        await gate.future;
        return tokens('access-2', 'refresh-2');
      };

      final results = Future.wait([
        session.refresh(),
        session.refresh(),
        session.validAccessToken(),
      ]);
      await Future<void>.delayed(Duration.zero);
      gate.complete();

      expect(await results, ['access-2', 'access-2', 'access-2']);
      expect(repo.refreshCalls, ['refresh-1']);
    });

    test('una renovación posterior vuelve a llamar al servidor', () async {
      store.value = 'refresh-1';
      var n = 1;
      repo.onRefresh = (_) async {
        n++;
        return tokens('access-$n', 'refresh-$n');
      };

      await session.refresh();
      await session.refresh();

      expect(repo.refreshCalls, ['refresh-1', 'refresh-2']);
      expect(store.value, 'refresh-3');
    });

    test(
      'invalid_token termina la sesión: borra el almacén y devuelve null',
      () async {
        await session.start(tokens('access-1', 'refresh-1'));
        repo.onRefresh = (_) async => throw _tokenInvalido;

        expect(await session.refresh(), isNull);

        expect(store.value, isNull);
        // Ya no queda access token en memoria: pedirlo no resucita nada
        expect(await session.validAccessToken(), isNull);
      },
    );

    for (final code in ['network', 'rate_limited', 'server_busy', 'http_502']) {
      test(
        '"$code" NO cierra la sesión: se relanza y el token se conserva',
        () async {
          store.value = 'refresh-1';
          repo.onRefresh = (_) async =>
              throw ApiFailure(code: code, message: 'fallo transitorio');

          await expectLater(
            session.refresh(),
            throwsA(isA<ApiFailure>().having((f) => f.code, 'code', code)),
          );

          expect(store.value, 'refresh-1');
        },
      );
    }

    test('tras un fallo transitorio se puede reintentar', () async {
      store.value = 'refresh-1';
      repo.onRefresh = (_) async => throw const ApiFailure.network();
      await expectLater(session.refresh(), throwsA(isA<ApiFailure>()));

      repo.onRefresh = (_) async => tokens('access-2', 'refresh-2');

      expect(await session.refresh(), 'access-2');
      expect(repo.refreshCalls, ['refresh-1', 'refresh-1']);
    });
  });

  group('end (cerrar sesión)', () {
    test(
      'borra lo local y revoca en el servidor el refresh guardado',
      () async {
        await session.start(tokens('access-1', 'refresh-1'));
        repo.onLogout = (_) async {};

        await session.end();

        expect(repo.logoutCalls, ['refresh-1']);
        expect(store.value, isNull);
        expect(await session.validAccessToken(), isNull);
      },
    );

    test(
      'si el servidor no responde, igual deja la sesión borrada y no lanza',
      () async {
        await session.start(tokens('access-1', 'refresh-1'));
        repo.onLogout = (_) async => throw const ApiFailure.network();

        await session.end();

        expect(store.value, isNull);
        expect(await session.validAccessToken(), isNull);
      },
    );

    test('sin sesión no llama al servidor', () async {
      await session.end();

      expect(repo.logoutCalls, isEmpty);
    });

    test(
      'espera a una renovación en curso y no la deja resucitar la sesión',
      () async {
        store.value = 'refresh-1';
        final gate = Completer<void>();
        repo.onRefresh = (_) async {
          await gate.future;
          return tokens('access-2', 'refresh-2');
        };
        repo.onLogout = (_) async {};

        final refreshing = session.refresh();
        await Future<void>.delayed(Duration.zero);
        final ending = session.end();
        gate.complete();
        await refreshing;
        await ending;

        expect(store.value, isNull);
        expect(await session.validAccessToken(), isNull);
        // El servidor rotó a refresh-2: se revoca lo último que hubo, no el viejo
        expect(repo.logoutCalls, ['refresh-2']);
      },
    );
  });
}
