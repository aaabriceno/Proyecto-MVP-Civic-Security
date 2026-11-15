import 'package:civic_security/features/auth/domain/auth_models.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _user({
  Object? alias = 'Halcon-482',
  Object? nivel = 'invitado',
}) => {
  'id': '89e95dd3-b844-4c68-8186-c778448e407a',
  'alias': alias,
  'nivel': nivel,
};

Map<String, dynamic> _tokens({
  Object? access = 'access-123',
  Object? refresh = 'refresh-456',
  Object? expiresIn = 900,
}) => {
  'access_token': access,
  'refresh_token': refresh,
  'expires_in': expiresIn,
};

void main() {
  group('AuthUser: datos del perfil (desde y cupo)', () {
    Map<String, dynamic> base() => {
      'id': '89e95dd3-b844-4c68-8186-c778448e407a',
      'alias': 'Halcon-482',
      'nivel': 'invitado',
    };

    test('lee desde (año y mes) y el cupo del día', () {
      final user = AuthUser.tryFromJson({
        ...base(),
        'desde': '2026-09',
        'cupo': {'usados': 1, 'maximo': 3},
      })!;

      expect(user.desde, DateTime(2026, 9));
      expect(user.cupo!.usados, 1);
      expect(user.cupo!.maximo, 3);
      expect(user.cupo!.restantes, 2);
    });

    test('sin esos datos (registro, login) la cuenta sigue siendo válida', () {
      final user = AuthUser.tryFromJson(base())!;

      expect(user.desde, isNull);
      expect(user.cupo, isNull);
    });

    test('un desde o un cupo malformado se ignora, no invalida la cuenta', () {
      for (final malo in <Map<String, dynamic>>[
        {'desde': 'septiembre'},
        {'desde': '2026-13'},
        {'desde': 5},
        {'cupo': 'mucho'},
        {
          'cupo': {'usados': 'x', 'maximo': 3},
        },
        {
          'cupo': {'usados': -1, 'maximo': 3},
        },
        {
          'cupo': {'usados': 1, 'maximo': 0},
        },
      ]) {
        final user = AuthUser.tryFromJson({...base(), ...malo});

        expect(user, isNotNull, reason: '$malo');
        expect(
          user!.desde == null || user.cupo == null,
          isTrue,
          reason: '$malo',
        );
      }
    });

    test('los restantes nunca son negativos', () {
      const cupo = ReportQuota(usados: 5, maximo: 3);

      expect(cupo.restantes, 0);
    });
  });

  group('AuthUser.tryFromJson', () {
    test('lee id, alias y nivel', () {
      final user = AuthUser.tryFromJson(_user());

      expect(user, isNotNull);
      expect(user!.id, '89e95dd3-b844-4c68-8186-c778448e407a');
      expect(user.alias, 'Halcon-482');
      expect(user.nivel, AuthLevel.invitado);
    });

    test('entiende el nivel verificado', () {
      expect(
        AuthUser.tryFromJson(_user(nivel: 'verificado'))!.nivel,
        AuthLevel.verificado,
      );
    });

    test(
      'un nivel que esta versión no conoce da null (servidor más nuevo)',
      () {
        expect(AuthUser.tryFromJson(_user(nivel: 'moderador')), isNull);
      },
    );

    test('faltan campos o tienen otro tipo: null, sin lanzar errores', () {
      expect(AuthUser.tryFromJson(_user(alias: null)), isNull);
      expect(AuthUser.tryFromJson(_user(alias: 123)), isNull);
      expect(AuthUser.tryFromJson(_user(alias: '')), isNull);
      expect(AuthUser.tryFromJson({'alias': 'x', 'nivel': 'invitado'}), isNull);
      expect(AuthUser.tryFromJson(const {}), isNull);
    });
  });

  group('AuthTokens.tryFromJson', () {
    test('lee los dos tokens y la duración del access token', () {
      final tokens = AuthTokens.tryFromJson(_tokens());

      expect(tokens, isNotNull);
      expect(tokens!.accessToken, 'access-123');
      expect(tokens.refreshToken, 'refresh-456');
      expect(tokens.expiresIn, const Duration(seconds: 900));
    });

    test('faltan campos, vienen vacíos o con otro tipo: null', () {
      expect(AuthTokens.tryFromJson(_tokens(access: null)), isNull);
      expect(AuthTokens.tryFromJson(_tokens(access: '')), isNull);
      expect(AuthTokens.tryFromJson(_tokens(refresh: 42)), isNull);
      expect(AuthTokens.tryFromJson(_tokens(refresh: '')), isNull);
      expect(AuthTokens.tryFromJson(_tokens(expiresIn: '900')), isNull);
      expect(AuthTokens.tryFromJson(_tokens(expiresIn: 0)), isNull);
      expect(AuthTokens.tryFromJson(_tokens(expiresIn: -1)), isNull);
      expect(AuthTokens.tryFromJson(const {}), isNull);
    });

    test('toString no deja ver los tokens (podrían acabar en un log)', () {
      final text = AuthTokens.tryFromJson(_tokens())!.toString();

      expect(text, isNot(contains('access-123')));
      expect(text, isNot(contains('refresh-456')));
    });
  });

  group('AuthSession.tryFromJson', () {
    test(
      'une el usuario y los tokens de una respuesta de login o registro',
      () {
        final session = AuthSession.tryFromJson({
          'user': _user(),
          ..._tokens(),
        });

        expect(session, isNotNull);
        expect(session!.user.alias, 'Halcon-482');
        expect(session.tokens.refreshToken, 'refresh-456');
      },
    );

    test('si falta el usuario o los tokens, es null', () {
      expect(AuthSession.tryFromJson(_tokens()), isNull);
      expect(AuthSession.tryFromJson({'user': _user()}), isNull);
      expect(
        AuthSession.tryFromJson({'user': 'no-es-un-mapa', ..._tokens()}),
        isNull,
      );
    });
  });
}
