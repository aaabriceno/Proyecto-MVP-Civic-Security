import 'package:civic_security/core/network/api_failure.dart';
import 'package:civic_security/features/auth/presentation/auth_failure_message.dart';
import 'package:flutter_test/flutter_test.dart';

ApiFailure _failure(
  String code, {
  Duration? retryAfter,
  Map<String, List<String>> fields = const {},
}) => ApiFailure(
  code: code,
  message: 'texto del servidor',
  retryAfter: retryAfter,
  fields: fields,
);

void main() {
  group('authFailureMessage', () {
    test('credenciales incorrectas: no dice si falló el alias o la clave', () {
      final message = authFailureMessage(_failure('invalid_credentials'));

      expect(message, 'Alias o contraseña incorrectos.');
    });

    test('cuenta bloqueada: explica que hay que esperar', () {
      final message = authFailureMessage(_failure('account_locked'));

      expect(message, contains('intentos'));
      expect(message.toLowerCase(), contains('espera'));
    });

    test('límite de solicitudes y servidor ocupado piden esperar', () {
      expect(
        authFailureMessage(_failure('rate_limited')).toLowerCase(),
        contains('espera'),
      );
      expect(authFailureMessage(_failure('server_busy')), contains('ocupado'));
    });

    test('sin conexión', () {
      expect(
        authFailureMessage(const ApiFailure.network()),
        contains('conexión'),
      );
    });

    test('datos inválidos: remite a los campos marcados', () {
      expect(
        authFailureMessage(_failure('validation_failed')),
        contains('Revisa'),
      );
    });

    test('cualquier otro error da un mensaje genérico y nunca el del '
        'servidor (puede traer detalles internos)', () {
      for (final code in ['unexpected', 'invalid_response', 'http_502', 'x']) {
        final message = authFailureMessage(_failure(code));

        expect(message, isNot(contains('texto del servidor')), reason: code);
        expect(message, contains('Inténtalo'), reason: code);
      }
    });
  });

  group('waitFor (cuánto esperar antes de reintentar)', () {
    test('en cuenta bloqueada, límite y servidor ocupado usa retry-after', () {
      const espera = Duration(seconds: 45);

      for (final code in ['account_locked', 'rate_limited', 'server_busy']) {
        expect(
          waitFor(_failure(code, retryAfter: espera)),
          espera,
          reason: code,
        );
      }
    });

    test('sin retry-after no hay cuenta regresiva', () {
      expect(waitFor(_failure('account_locked')), isNull);
    });

    test(
      'un error que no es de espera la ignora aunque el servidor la mande',
      () {
        expect(
          waitFor(
            _failure(
              'invalid_credentials',
              retryAfter: const Duration(seconds: 5),
            ),
          ),
          isNull,
        );
      },
    );
  });

  group('fieldErrorOf (error de un campo del formulario)', () {
    final failure = _failure(
      'validation_failed',
      fields: {
        'alias': ['ya está en uso', 'otro'],
        'password': [],
      },
    );

    test('devuelve el primer mensaje del campo', () {
      expect(fieldErrorOf(failure, 'alias'), 'ya está en uso');
    });

    test('null si el campo no tiene errores, está vacío o no hay fallo', () {
      expect(fieldErrorOf(failure, 'password'), isNull);
      expect(fieldErrorOf(failure, 'acepta_consentimiento'), isNull);
      expect(fieldErrorOf(null, 'alias'), isNull);
    });
  });

  group('formatCountdown (m:ss)', () {
    test('segundos y minutos', () {
      expect(formatCountdown(const Duration(seconds: 45)), '0:45');
      expect(formatCountdown(const Duration(seconds: 65)), '1:05');
      expect(formatCountdown(const Duration(minutes: 10)), '10:00');
    });

    test('cero y negativo se muestran como 0:00', () {
      expect(formatCountdown(Duration.zero), '0:00');
      expect(formatCountdown(const Duration(seconds: -3)), '0:00');
    });

    test('redondea hacia arriba: con 200 ms de espera todavía falta 1 s', () {
      expect(formatCountdown(const Duration(milliseconds: 200)), '0:01');
    });
  });
}
