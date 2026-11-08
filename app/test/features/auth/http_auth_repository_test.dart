import 'package:civic_security/core/network/api_failure.dart';
import 'package:civic_security/features/auth/data/auth_repository.dart';
import 'package:civic_security/features/auth/domain/auth_models.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../core/fake_http_adapter.dart';

Map<String, dynamic> _sessionBody({String nivel = 'invitado'}) => {
  'data': {
    'user': {
      'id': '89e95dd3-b844-4c68-8186-c778448e407a',
      'alias': 'Halcon-482',
      'nivel': nivel,
    },
    'access_token': 'access-123',
    'refresh_token': 'refresh-456',
    'expires_in': 900,
  },
};

Map<String, dynamic> _errorBody(
  String code, [
  Map<String, dynamic>? fields,
]) => {
  'error': {'code': code, 'message': 'mensaje del servidor', 'fields': ?fields},
};

HttpAuthRepository _repo(FakeHttpAdapter adapter) =>
    HttpAuthRepository(fakeDio(adapter));

/// Ejecuta [call] y devuelve el [ApiFailure] que lanza.
Future<ApiFailure> _failureOf(Future<Object?> Function() call) async {
  try {
    await call();
  } on ApiFailure catch (failure) {
    return failure;
  }
  fail('Debió lanzar un ApiFailure');
}

void main() {
  group('register', () {
    test(
      'envía alias, contraseña y consentimiento, y devuelve la sesión',
      () async {
        final adapter = FakeHttpAdapter(201, _sessionBody());

        final session = await _repo(adapter).register(
          alias: 'Halcon-482',
          password: 'una contraseña larga y segura',
          acceptsConsent: true,
        );

        expect(adapter.last!.method, 'POST');
        expect(adapter.last!.path, '/v1/auth/register');
        expect(adapter.last!.data, {
          'alias': 'Halcon-482',
          'password': 'una contraseña larga y segura',
          'acepta_consentimiento': true,
        });
        expect(session.user.alias, 'Halcon-482');
        expect(session.user.nivel, AuthLevel.invitado);
        expect(session.tokens.accessToken, 'access-123');
        expect(session.tokens.refreshToken, 'refresh-456');
      },
    );

    test('un 422 conserva el detalle por campo', () async {
      final adapter = FakeHttpAdapter(
        422,
        _errorBody('validation_failed', {
          'alias': ['ya está en uso'],
        }),
      );

      final failure = await _failureOf(
        () => _repo(adapter).register(
          alias: 'Halcon-482',
          password: 'una contraseña larga y segura',
          acceptsConsent: true,
        ),
      );

      expect(failure.code, 'validation_failed');
      expect(failure.fields['alias'], ['ya está en uso']);
    });
  });

  group('login', () {
    test('envía alias y contraseña, y devuelve la sesión', () async {
      final adapter = FakeHttpAdapter(200, _sessionBody(nivel: 'verificado'));

      final session = await _repo(
        adapter,
      ).login(alias: 'Halcon-482', password: 'una contraseña larga y segura');

      expect(adapter.last!.method, 'POST');
      expect(adapter.last!.path, '/v1/auth/login');
      expect(adapter.last!.data, {
        'alias': 'Halcon-482',
        'password': 'una contraseña larga y segura',
      });
      expect(session.user.nivel, AuthLevel.verificado);
    });

    test('un 401 es invalid_credentials', () async {
      final adapter = FakeHttpAdapter(401, _errorBody('invalid_credentials'));

      final failure = await _failureOf(
        () => _repo(adapter).login(alias: 'x', password: 'y'),
      );

      expect(failure.code, 'invalid_credentials');
    });

    test('una cuenta bloqueada trae cuánto esperar', () async {
      final adapter = FakeHttpAdapter(
        429,
        _errorBody('account_locked'),
        headers: {
          'retry-after': ['42'],
        },
      );

      final failure = await _failureOf(
        () => _repo(adapter).login(alias: 'x', password: 'y'),
      );

      expect(failure.code, 'account_locked');
      expect(failure.retryAfter, const Duration(seconds: 42));
    });

    test('sin conexión es un error de red', () async {
      final adapter = FakeHttpAdapter(
        0,
        null,
        error: DioException(
          requestOptions: RequestOptions(path: '/v1/auth/login'),
          type: DioExceptionType.connectionError,
        ),
      );

      final failure = await _failureOf(
        () => _repo(adapter).login(alias: 'x', password: 'y'),
      );

      expect(failure.code, 'network');
    });

    test('una respuesta 200 sin tokens no se acepta como sesión', () async {
      final adapter = FakeHttpAdapter(200, {
        'data': {
          'user': {'id': 'x', 'alias': 'Halcon-482', 'nivel': 'invitado'},
        },
      });

      final failure = await _failureOf(
        () => _repo(adapter).login(alias: 'x', password: 'y'),
      );

      expect(failure.code, 'invalid_response');
    });

    test('una respuesta 200 que no es JSON tampoco', () async {
      final adapter = FakeHttpAdapter(200, '<html>proxy</html>');

      final failure = await _failureOf(
        () => _repo(adapter).login(alias: 'x', password: 'y'),
      );

      expect(failure.code, 'invalid_response');
    });
  });

  group('refresh', () {
    test('envía el refresh token y devuelve el par nuevo', () async {
      final adapter = FakeHttpAdapter(200, {
        'data': {
          'access_token': 'access-nuevo',
          'refresh_token': 'refresh-nuevo',
          'expires_in': 900,
        },
      });

      final tokens = await _repo(adapter).refresh('refresh-viejo');

      expect(adapter.last!.path, '/v1/auth/refresh');
      expect(adapter.last!.data, {'refresh_token': 'refresh-viejo'});
      expect(tokens.accessToken, 'access-nuevo');
      expect(tokens.refreshToken, 'refresh-nuevo');
    });

    test('un 401 es invalid_token', () async {
      final adapter = FakeHttpAdapter(401, _errorBody('invalid_token'));

      final failure = await _failureOf(() => _repo(adapter).refresh('x'));

      expect(failure.code, 'invalid_token');
    });
  });

  group('logout', () {
    test('envía el refresh token y termina con un 204 vacío', () async {
      final adapter = FakeHttpAdapter(204, null);

      await _repo(adapter).logout('refresh-456');

      expect(adapter.last!.method, 'POST');
      expect(adapter.last!.path, '/v1/auth/logout');
      expect(adapter.last!.data, {'refresh_token': 'refresh-456'});
    });

    test(
      'sin conexión lanza un error de red (quien llama decide qué hacer)',
      () async {
        final adapter = FakeHttpAdapter(
          0,
          null,
          error: DioException(
            requestOptions: RequestOptions(path: '/v1/auth/logout'),
            type: DioExceptionType.connectionTimeout,
          ),
        );

        final failure = await _failureOf(() => _repo(adapter).logout('x'));

        expect(failure.code, 'network');
      },
    );
  });

  group('me', () {
    test('envía el access token como Bearer y devuelve la cuenta', () async {
      final adapter = FakeHttpAdapter(200, {
        'data': {
          'id': '89e95dd3-b844-4c68-8186-c778448e407a',
          'alias': 'Halcon-482',
          'nivel': 'invitado',
        },
      });

      final user = await _repo(adapter).me('access-123');

      expect(adapter.last!.method, 'GET');
      expect(adapter.last!.path, '/v1/me');
      expect(adapter.last!.headers['authorization'], 'Bearer access-123');
      expect(user.alias, 'Halcon-482');
    });

    test('un 401 es unauthorized', () async {
      final adapter = FakeHttpAdapter(401, _errorBody('unauthorized'));

      final failure = await _failureOf(() => _repo(adapter).me('x'));

      expect(failure.code, 'unauthorized');
    });
  });

  group('lo que NO se envía', () {
    test(
      'registro, login, refresh y logout no mandan cabecera Authorization',
      () async {
        final adapter = FakeHttpAdapter(200, _sessionBody());
        final repo = _repo(adapter);

        await repo.register(alias: 'a', password: 'b', acceptsConsent: true);
        expect(adapter.last!.headers.containsKey('authorization'), isFalse);

        await repo.login(alias: 'a', password: 'b');
        expect(adapter.last!.headers.containsKey('authorization'), isFalse);
      },
    );
  });
}
