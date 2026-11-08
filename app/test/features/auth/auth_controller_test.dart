import 'dart:async';

import 'package:civic_security/core/network/api_failure.dart';
import 'package:civic_security/core/storage/token_store.dart';
import 'package:civic_security/features/auth/data/auth_repository.dart';
import 'package:civic_security/features/auth/domain/auth_models.dart';
import 'package:civic_security/features/auth/presentation/auth_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

const _user = AuthUser(
  id: '89e95dd3-b844-4c68-8186-c778448e407a',
  alias: 'Halcon-482',
  nivel: AuthLevel.invitado,
);

AuthSession _session([
  String access = 'access-1',
  String refresh = 'refresh-1',
]) => AuthSession(user: _user, tokens: tokens(access, refresh));

ApiFailure _failure(String code) => ApiFailure(code: code, message: code);

void main() {
  late InMemoryTokenStore store;
  late FakeAuthRepository repo;
  late ProviderContainer container;

  AuthState state() => container.read(authControllerProvider);
  AuthController controller() =>
      container.read(authControllerProvider.notifier);

  setUp(() {
    store = InMemoryTokenStore();
    repo = FakeAuthRepository()..onLogout = (_) async {};
    container = ProviderContainer(
      overrides: [
        tokenStoreProvider.overrideWithValue(store),
        authRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);
  });

  test('antes de recuperar la sesión el estado es loading', () {
    expect(state().status, AuthStatus.loading);
    expect(state().user, isNull);
    expect(state().busy, isFalse);
  });

  group('restore (al abrir la app)', () {
    test('sin sesión guardada: signedOut y no llama al servidor', () async {
      await controller().restore();

      expect(state().status, AuthStatus.signedOut);
      expect(repo.refreshCalls, isEmpty);
      expect(repo.meCalls, isEmpty);
    });

    test(
      'con sesión guardada: renueva, pide la cuenta y queda signedIn',
      () async {
        store.value = 'refresh-1';
        repo.onRefresh = (_) async => tokens('access-2', 'refresh-2');
        repo.onMe = (_) async => _user;

        await controller().restore();

        expect(state().status, AuthStatus.signedIn);
        expect(state().user?.alias, 'Halcon-482');
        expect(repo.meCalls, ['access-2']);
        expect(store.value, 'refresh-2');
      },
    );

    test(
      'si el servidor ya no reconoce la sesión: signedOut y almacén vacío',
      () async {
        store.value = 'refresh-1';
        repo.onRefresh = (_) async => throw _failure('invalid_token');

        await controller().restore();

        expect(state().status, AuthStatus.signedOut);
        expect(store.value, isNull);
      },
    );

    test('sin señal: offline, y la sesión guardada se conserva', () async {
      store.value = 'refresh-1';
      repo.onRefresh = (_) async => throw const ApiFailure.network();

      await controller().restore();

      expect(state().status, AuthStatus.offline);
      expect(state().user, isNull);
      expect(store.value, 'refresh-1');
      expect(repo.meCalls, isEmpty);
    });

    test(
      'renovó bien pero /me falla por red: offline (la sesión ya está a salvo)',
      () async {
        store.value = 'refresh-1';
        repo.onRefresh = (_) async => tokens('access-2', 'refresh-2');
        repo.onMe = (_) async => throw const ApiFailure.network();

        await controller().restore();

        expect(state().status, AuthStatus.offline);
        expect(store.value, 'refresh-2');
      },
    );

    test(
      'si /me rechaza el token recién emitido: signedOut y se cierra la sesión',
      () async {
        store.value = 'refresh-1';
        repo.onRefresh = (_) async => tokens('access-2', 'refresh-2');
        repo.onMe = (_) async => throw _failure('unauthorized');

        await controller().restore();

        expect(state().status, AuthStatus.signedOut);
        expect(store.value, isNull);
      },
    );

    test(
      'desde offline, reintentar con señal deja la sesión signedIn',
      () async {
        store.value = 'refresh-1';
        repo.onRefresh = (_) async => throw const ApiFailure.network();
        await controller().restore();
        expect(state().status, AuthStatus.offline);

        repo.onRefresh = (_) async => tokens('access-2', 'refresh-2');
        repo.onMe = (_) async => _user;
        await controller().restore();

        expect(state().status, AuthStatus.signedIn);
      },
    );

    test('dos restore a la vez hacen una sola ronda de llamadas', () async {
      store.value = 'refresh-1';
      final gate = Completer<void>();
      repo
        ..onRefresh = (_) async {
          await gate.future;
          return tokens('access-2', 'refresh-2');
        }
        ..onMe = (_) async => _user;

      final a = controller().restore();
      final b = controller().restore();
      gate.complete();
      await Future.wait([a, b]);

      expect(repo.refreshCalls, hasLength(1));
      expect(repo.meCalls, hasLength(1));
    });

    test(
      'un error inesperado no deja la app en loading para siempre',
      () async {
        store.value = 'refresh-1';
        repo.onRefresh = (_) async => throw StateError('algo raro');

        await controller().restore();

        expect(state().status, AuthStatus.signedOut);
        expect(state().failure?.code, 'unexpected');
      },
    );
  });

  group('register', () {
    test('éxito: signedIn y la sesión queda guardada', () async {
      repo.onRegister = (_, _, _) async => _session();

      await controller().register(
        alias: 'Halcon-482',
        password: 'una contraseña larga y segura',
        acceptsConsent: true,
      );

      expect(state().status, AuthStatus.signedIn);
      expect(state().user?.alias, 'Halcon-482');
      expect(state().busy, isFalse);
      expect(state().failure, isNull);
      expect(store.value, 'refresh-1');
    });

    test(
      'un 422 deja el detalle por campo y no guarda ninguna sesión',
      () async {
        repo.onRegister = (_, _, _) async => throw const ApiFailure(
          code: 'validation_failed',
          message: 'Datos inválidos',
          fields: {
            'alias': ['ya está en uso'],
          },
        );

        await controller().register(
          alias: 'Halcon-482',
          password: 'una contraseña larga y segura',
          acceptsConsent: true,
        );

        expect(state().status, AuthStatus.signedOut);
        expect(state().busy, isFalse);
        expect(state().failure?.code, 'validation_failed');
        expect(state().failure?.fields['alias'], ['ya está en uso']);
        expect(store.value, isNull);
      },
    );

    test(
      'mientras envía, busy es true y un segundo toque no hace nada',
      () async {
        final gate = Completer<AuthSession>();
        repo.onRegister = (_, _, _) => gate.future;

        final first = controller().register(
          alias: 'Halcon-482',
          password: 'una contraseña larga y segura',
          acceptsConsent: true,
        );
        await Future<void>.delayed(Duration.zero);
        expect(state().busy, isTrue);

        await controller().register(
          alias: 'Halcon-482',
          password: 'una contraseña larga y segura',
          acceptsConsent: true,
        );
        expect(repo.registerCalls, hasLength(1));

        gate.complete(_session());
        await first;
        expect(state().status, AuthStatus.signedIn);
      },
    );

    test('un nuevo intento borra el error anterior', () async {
      repo.onRegister = (_, _, _) async => throw const ApiFailure.network();
      await controller().register(
        alias: 'a',
        password: 'b',
        acceptsConsent: true,
      );
      expect(state().failure?.code, 'network');

      final gate = Completer<AuthSession>();
      repo.onRegister = (_, _, _) => gate.future;
      final second = controller().register(
        alias: 'a',
        password: 'b',
        acceptsConsent: true,
      );
      await Future<void>.delayed(Duration.zero);

      expect(state().failure, isNull);
      gate.complete(_session());
      await second;
    });

    test('un error inesperado no deja el botón bloqueado', () async {
      repo.onRegister = (_, _, _) async => throw StateError('algo raro');

      await controller().register(
        alias: 'a',
        password: 'b',
        acceptsConsent: true,
      );

      expect(state().busy, isFalse);
      expect(state().failure?.code, 'unexpected');
    });
  });

  group('login', () {
    test('éxito: signedIn y la sesión queda guardada', () async {
      repo.onLogin = (_, _) async => _session('access-1', 'refresh-9');

      await controller().login(alias: 'Halcon-482', password: 'x');

      expect(state().status, AuthStatus.signedIn);
      expect(store.value, 'refresh-9');
    });

    test('credenciales incorrectas: sigue signedOut con el error', () async {
      repo.onLogin = (_, _) async => throw _failure('invalid_credentials');

      await controller().login(alias: 'Halcon-482', password: 'mala');

      expect(state().status, AuthStatus.signedOut);
      expect(state().failure?.code, 'invalid_credentials');
      expect(store.value, isNull);
    });

    test('cuenta bloqueada: conserva cuánto esperar', () async {
      repo.onLogin = (_, _) async => throw const ApiFailure(
        code: 'account_locked',
        message: 'bloqueada',
        retryAfter: Duration(seconds: 42),
      );

      await controller().login(alias: 'Halcon-482', password: 'x');

      expect(state().failure?.code, 'account_locked');
      expect(state().failure?.retryAfter, const Duration(seconds: 42));
    });

    test('no hace nada si ya hay una sesión iniciada', () async {
      repo.onLogin = (_, _) async => _session();
      await controller().login(alias: 'Halcon-482', password: 'x');

      await controller().login(alias: 'Otro', password: 'y');

      expect(repo.loginCalls, ['Halcon-482']);
    });
  });

  group('logout', () {
    test('queda signedOut al instante, sin esperar al servidor', () async {
      repo.onLogin = (_, _) async => _session();
      await controller().login(alias: 'Halcon-482', password: 'x');
      final gate = Completer<void>();
      repo.onLogout = (_) => gate.future;

      final closing = controller().logout();
      await Future<void>.delayed(Duration.zero);

      expect(state().status, AuthStatus.signedOut);
      expect(state().user, isNull);

      gate.complete();
      await closing;
      expect(store.value, isNull);
    });

    test('sin conexión igual se cierra la sesión local', () async {
      repo.onLogin = (_, _) async => _session();
      await controller().login(alias: 'Halcon-482', password: 'x');
      repo.onLogout = (_) async => throw const ApiFailure.network();

      await controller().logout();

      expect(state().status, AuthStatus.signedOut);
      expect(state().failure, isNull);
      expect(store.value, isNull);
    });

    test(
      'tras cerrar sesión, abrir la app otra vez no recupera nada',
      () async {
        repo.onLogin = (_, _) async => _session();
        await controller().login(alias: 'Halcon-482', password: 'x');
        await controller().logout();

        await controller().restore();

        expect(state().status, AuthStatus.signedOut);
        expect(repo.refreshCalls, isEmpty);
      },
    );
  });

  test('clearFailure borra el error y deja lo demás igual', () async {
    repo.onLogin = (_, _) async => throw _failure('invalid_credentials');
    await controller().login(alias: 'a', password: 'b');
    expect(state().failure, isNotNull);

    controller().clearFailure();

    expect(state().failure, isNull);
    expect(state().status, AuthStatus.signedOut);
  });
}
