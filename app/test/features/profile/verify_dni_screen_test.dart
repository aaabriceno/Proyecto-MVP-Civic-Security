import 'package:civic_security/features/auth/domain/auth_models.dart';
import 'package:civic_security/features/profile/presentation/verify_dni_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../auth/auth_widget_harness.dart' show failure;
import '../auth/fakes.dart';
import 'profile_harness.dart';

const _verificada = AuthUser(
  id: '89e95dd3-b844-4c68-8186-c778448e407a',
  alias: 'Halcon-Misti-482',
  nivel: AuthLevel.verificado,
  cupo: ReportQuota(usados: 0, maximo: 10),
);

FakeAuthRepository _repoOk() =>
    FakeAuthRepository()..onVerifyDni = ((_, _) async => _verificada);

Future<void> _escribe(WidgetTester tester, String dni) async {
  await tester.enterText(find.byKey(const Key('campo-dni')), dni);
  await tester.pump();
}

Future<void> _enviar(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('boton-verificar-dni')));
  await tester.pumpAndSettle();
}

FakeAuthRepository _repoFalla(String code, {Duration? retryAfter}) =>
    FakeAuthRepository()
      ..onVerifyDni = ((_, _) async =>
          throw failure(code, retryAfter: retryAfter));

void main() {
  testWidgets('explica qué se guarda y avisa que suplantar es delito', (
    tester,
  ) async {
    await pumpProfile(tester, const VerifyDniScreen(), repo: _repoOk());

    expect(find.byKey(const Key('campo-dni')), findsOneWidget);
    expect(find.byKey(const Key('boton-verificar-dni')), findsOneWidget);
    final privacidad = find.byKey(const Key('aviso-privacidad-dni'));
    expect(privacidad, findsOneWidget);
    expect(
      find.descendant(
        of: privacidad,
        matching: find.textContaining('No guardamos tu DNI'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('delito'), findsOneWidget);
  });

  testWidgets('en una pantalla alta el formulario empieza arriba', (
    tester,
  ) async {
    await pumpProfile(tester, const VerifyDniScreen(), repo: _repoOk());

    final arriba = tester.getTopLeft(find.byKey(const Key('campo-dni'))).dy;

    expect(arriba, lessThan(500));
  });

  group('el campo', () {
    testWidgets('solo acepta dígitos y como mucho 8', (tester) async {
      await pumpProfile(tester, const VerifyDniScreen(), repo: _repoOk());

      await _escribe(tester, '12ab 345-67890');

      final campo = tester.widget<TextField>(
        find.byKey(const Key('campo-dni')),
      );
      expect(campo.controller!.text, '12345678');
    });

    testWidgets('teclado numérico, sin sugerencias ni autocorrección', (
      tester,
    ) async {
      await pumpProfile(tester, const VerifyDniScreen(), repo: _repoOk());

      final campo = tester.widget<TextField>(
        find.byKey(const Key('campo-dni')),
      );

      expect(campo.keyboardType, TextInputType.number);
      expect(campo.autocorrect, isFalse);
      expect(campo.enableSuggestions, isFalse);
    });
  });

  group('validación en el teléfono (sin molestar al servidor)', () {
    testWidgets('con menos de 8 dígitos no llama al servidor', (tester) async {
      final repo = _repoOk();
      await pumpProfile(tester, const VerifyDniScreen(), repo: repo);
      await _escribe(tester, '1234567');

      await _enviar(tester);

      expect(find.text('Escribe los 8 dígitos de tu DNI.'), findsOneWidget);
      expect(repo.verifyDniCalls, isEmpty);
    });

    testWidgets('sin escribir nada tampoco', (tester) async {
      final repo = _repoOk();
      await pumpProfile(tester, const VerifyDniScreen(), repo: repo);

      await _enviar(tester);

      expect(find.text('Escribe los 8 dígitos de tu DNI.'), findsOneWidget);
      expect(repo.verifyDniCalls, isEmpty);
    });

    testWidgets('el error se quita al volver a escribir', (tester) async {
      await pumpProfile(tester, const VerifyDniScreen(), repo: _repoOk());
      await _escribe(tester, '123');
      await _enviar(tester);

      await _escribe(tester, '1234');

      expect(find.text('Escribe los 8 dígitos de tu DNI.'), findsNothing);
    });
  });

  testWidgets('con 8 dígitos lo envía, avisa y vuelve al perfil', (
    tester,
  ) async {
    final repo = _repoOk();
    await pumpProfile(tester, const VerifyDniScreen(), repo: repo);
    await _escribe(tester, '12345678');

    await _enviar(tester);

    expect(repo.verifyDniCalls, ['12345678']);
    expect(find.byType(VerifyDniScreen), findsNothing);
    expect(
      find.text('Cuenta verificada. Ya puedes reportar más veces al día.'),
      findsOneWidget,
    );
  });

  testWidgets('devuelve true al cerrar, para que el perfil se actualice', (
    tester,
  ) async {
    Object? resultado = 'sin cerrar';
    await pumpProfile(
      tester,
      const VerifyDniScreen(),
      repo: _repoOk(),
      onResult: (value) => resultado = value,
    );
    await _escribe(tester, '12345678');

    await _enviar(tester);

    expect(resultado, isTrue);
  });

  group('errores del servidor', () {
    testWidgets('un DNI que ya tiene cuenta se marca en su campo', (
      tester,
    ) async {
      await pumpProfile(
        tester,
        const VerifyDniScreen(),
        repo: _repoFalla('dni_taken'),
      );
      await _escribe(tester, '12345678');

      await _enviar(tester);

      expect(find.text('Este DNI ya tiene una cuenta.'), findsOneWidget);
      expect(find.byType(VerifyDniScreen), findsOneWidget);
      final campo = tester.widget<TextField>(
        find.byKey(const Key('campo-dni')),
      );
      expect(campo.controller!.text, '12345678', reason: 'por si fue un error');
      expect(find.text('texto del servidor'), findsNothing);
    });

    testWidgets('el error del campo se quita al corregir el número', (
      tester,
    ) async {
      await pumpProfile(
        tester,
        const VerifyDniScreen(),
        repo: _repoFalla('dni_taken'),
      );
      await _escribe(tester, '12345678');
      await _enviar(tester);

      await _escribe(tester, '12345679');

      expect(find.text('Este DNI ya tiene una cuenta.'), findsNothing);
    });

    testWidgets('un formato rechazado por el servidor se marca en el campo', (
      tester,
    ) async {
      final repo = FakeAuthRepository()
        ..onVerifyDni = ((_, _) async => throw failure(
          'validation_failed',
          fields: {
            'dni': ['debe tener 8 dígitos'],
          },
        ));
      await pumpProfile(tester, const VerifyDniScreen(), repo: repo);
      await _escribe(tester, '12345678');

      await _enviar(tester);

      expect(find.text('Escribe los 8 dígitos de tu DNI.'), findsOneWidget);
    });

    testWidgets('sin intentos del día lo dice y no deja volver a intentar', (
      tester,
    ) async {
      await pumpProfile(
        tester,
        const VerifyDniScreen(),
        repo: _repoFalla(
          'dni_attempts_exceeded',
          retryAfter: const Duration(hours: 3),
        ),
      );
      await _escribe(tester, '12345678');

      await _enviar(tester);

      final aviso = find.byKey(const Key('aviso-dni'));
      expect(aviso, findsOneWidget);
      expect(
        find.descendant(
          of: aviso,
          matching: find.textContaining('límite de intentos de hoy'),
        ),
        findsOneWidget,
      );
      final boton = tester.widget<FilledButton>(
        find.byKey(const Key('boton-verificar-dni')),
      );
      expect(boton.onPressed, isNull);
    });

    testWidgets('si la cuenta ya estaba verificada, lo dice', (tester) async {
      await pumpProfile(
        tester,
        const VerifyDniScreen(),
        repo: _repoFalla('already_verified'),
      );
      await _escribe(tester, '12345678');

      await _enviar(tester);

      expect(find.text('Tu cuenta ya está verificada.'), findsOneWidget);
      expect(
        find.byType(VerifyDniScreen),
        findsNothing,
        reason:
            'no hay nada que corregir: vuelve para que el perfil se actualice',
      );
    });

    testWidgets('sin conexión avisa y deja reintentar', (tester) async {
      final repo = _repoFalla('network');
      await pumpProfile(tester, const VerifyDniScreen(), repo: repo);
      await _escribe(tester, '12345678');

      await _enviar(tester);

      expect(find.textContaining('Sin conexión'), findsOneWidget);
      expect(find.text('texto del servidor'), findsNothing);
      final boton = tester.widget<FilledButton>(
        find.byKey(const Key('boton-verificar-dni')),
      );
      expect(boton.onPressed, isNotNull);
    });
  });

  testWidgets('mientras envía, el botón no deja enviar dos veces', (
    tester,
  ) async {
    final repo = FakeAuthRepository()
      ..onVerifyDni = ((_, _) => Future<AuthUser>.delayed(
        const Duration(seconds: 1),
        () => _verificada,
      ));
    await pumpProfile(tester, const VerifyDniScreen(), repo: repo);
    await _escribe(tester, '12345678');

    await tester.tap(find.byKey(const Key('boton-verificar-dni')));
    await tester.pump();
    await tester.tap(
      find.byKey(const Key('boton-verificar-dni')),
      warnIfMissed: false,
    );
    await tester.pump();
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(repo.verifyDniCalls, hasLength(1));
  });
}
