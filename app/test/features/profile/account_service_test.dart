import 'package:civic_security/core/network/api_failure.dart';
import 'package:civic_security/features/auth/data/session_manager.dart';
import 'package:civic_security/features/auth/domain/auth_models.dart';
import 'package:civic_security/features/profile/data/account_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../auth/fakes.dart';

const _user = AuthUser(
  id: '89e95dd3-b844-4c68-8186-c778448e407a',
  alias: 'Halcon-482',
  nivel: AuthLevel.invitado,
);

void main() {
  late InMemoryTokenStore store;
  late FakeAuthRepository repo;
  late SessionManager session;
  late AccountService service;

  setUp(() {
    store = InMemoryTokenStore();
    repo = FakeAuthRepository();
    session = SessionManager(repository: repo, store: store);
    service = AccountService(repository: repo, session: session);
  });

  group('me', () {
    test('pide el perfil con el access token vigente', () async {
      await session.start(tokens('access-1', 'refresh-1'));
      repo.onMe = (_) async => _user;

      final user = await service.me();

      expect(user.alias, 'Halcon-482');
      expect(repo.meCalls, ['access-1']);
    });

    test('sin sesión falla con unauthorized y no llama al servidor', () async {
      await expectLater(
        service.me(),
        throwsA(
          isA<ApiFailure>().having((e) => e.code, 'code', 'unauthorized'),
        ),
      );
      expect(repo.meCalls, isEmpty);
    });
  });

  group('verifyDni', () {
    test('manda el DNI con la sesión actual y devuelve la cuenta', () async {
      await session.start(tokens('access-1', 'refresh-1'));
      repo.onVerifyDni = (_, _) async => const AuthUser(
        id: '89e95dd3-b844-4c68-8186-c778448e407a',
        alias: 'Halcon-482',
        nivel: AuthLevel.verificado,
      );

      final user = await service.verifyDni('12345678');

      expect(user.nivel, AuthLevel.verificado);
      expect(repo.verifyDniCalls, ['12345678']);
    });

    test('sin sesión falla con unauthorized y no llama al servidor', () async {
      await expectLater(
        service.verifyDni('12345678'),
        throwsA(
          isA<ApiFailure>().having((e) => e.code, 'code', 'unauthorized'),
        ),
      );
      expect(repo.verifyDniCalls, isEmpty);
    });
  });

  group('changePassword', () {
    setUp(() async {
      await session.start(tokens('access-1', 'refresh-1'));
    });

    test('manda las dos contraseñas con la sesión actual', () async {
      repo.onChangePassword = (_, _, _) async =>
          AuthSession(user: _user, tokens: tokens('access-2', 'refresh-2'));

      await service.changePassword(current: 'la actual', next: 'la nueva');

      expect(repo.changePasswordCalls, [
        (current: 'la actual', next: 'la nueva'),
      ]);
    });

    test(
      'guarda la sesión nueva: el refresh token anterior ya no sirve',
      () async {
        repo.onChangePassword = (_, _, _) async =>
            AuthSession(user: _user, tokens: tokens('access-2', 'refresh-2'));

        await service.changePassword(current: 'la actual', next: 'la nueva');

        expect(store.value, 'refresh-2');
        expect(await session.validAccessToken(), 'access-2');
      },
    );

    test('si el servidor la rechaza, la sesión no cambia', () async {
      repo.onChangePassword = (_, _, _) async => throw const ApiFailure(
        code: 'validation_failed',
        message: 'x',
        fields: {
          'current_password': ['es incorrecta'],
        },
      );

      await expectLater(
        service.changePassword(current: 'mala', next: 'la nueva'),
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.fields['current_password'],
            'fields',
            ['es incorrecta'],
          ),
        ),
      );

      expect(store.value, 'refresh-1');
      expect(await session.validAccessToken(), 'access-1');
    });

    test('sin sesión falla con unauthorized', () async {
      repo.onLogout = (_) async {};
      await session.end();

      await expectLater(
        service.changePassword(current: 'a', next: 'b'),
        throwsA(
          isA<ApiFailure>().having((e) => e.code, 'code', 'unauthorized'),
        ),
      );
      expect(repo.changePasswordCalls, isEmpty);
    });
  });

  group('deleteAccount', () {
    setUp(() async {
      await session.start(tokens('access-1', 'refresh-1'));
    });

    test('manda la contraseña con la sesión actual', () async {
      repo.onDeleteAccount = (_, _) async {};

      await service.deleteAccount(password: 'mi contraseña');

      expect(repo.deleteAccountCalls, ['mi contraseña']);
    });

    test(
      'un error del servidor se relanza y no toca la sesión local',
      () async {
        repo.onDeleteAccount = (_, _) async => throw const ApiFailure(
          code: 'validation_failed',
          message: 'x',
          fields: {
            'password': ['es incorrecta'],
          },
        );

        await expectLater(
          service.deleteAccount(password: 'mala'),
          throwsA(isA<ApiFailure>()),
        );

        expect(store.value, 'refresh-1');
      },
    );
  });
}
