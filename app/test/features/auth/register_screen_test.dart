import 'dart:async';
import 'dart:math';

import 'package:civic_security/core/network/api_failure.dart';
import 'package:civic_security/features/auth/domain/alias_suggester.dart';
import 'package:civic_security/features/auth/presentation/register_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'auth_widget_harness.dart';
import 'fakes.dart';

const _alias = Key('campo-alias');
const _otro = Key('boton-otro-alias');
const _password = Key('campo-contrasena');
const _mostrar = Key('boton-mostrar-contrasena');
const _consent = Key('checkbox-consentimiento');
const _crear = Key('boton-crear-cuenta');

String _aliasActual(WidgetTester tester) =>
    tester.widget<TextField>(find.byKey(_alias)).controller!.text;

Future<FakeAuthRepository> _abrir(
  WidgetTester tester, {
  VoidCallback? onBack,
}) async {
  final repo = FakeAuthRepository()..onLogout = (_) async {};
  await pumpAuth(
    tester,
    RegisterScreen(
      onBack: onBack ?? () {},
      suggester: AliasSuggester(Random(1)),
    ),
    repo: repo,
  );
  return repo;
}

Future<void> _llenarYMarcar(WidgetTester tester, {String? password}) async {
  await tester.enterText(find.byKey(_password), password ?? goodPassword);
  await tester.tap(find.byKey(_consent));
  await tester.pump();
}

Future<void> _crearCuenta(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(_crear));
  await tester.tap(find.byKey(_crear));
  await tester.pump();
}

void main() {
  group('lo que se ve (frame 03)', () {
    testWidgets('título, subtítulo y un alias sugerido de entrada', (
      tester,
    ) async {
      await _abrir(tester);

      expect(find.text('Crea tu cuenta anónima'), findsOneWidget);
      expect(
        find.textContaining('No pedimos nombre ni apellido'),
        findsOneWidget,
      );
      expect(
        _aliasActual(tester),
        matches(RegExp(r'^[A-Z][a-z]+-[A-Z][a-z]+-\d{3}$')),
      );
      expect(find.textContaining('Generado al azar'), findsOneWidget);
    });

    testWidgets('no pide teléfono ni envía códigos (se verifica por DNI)', (
      tester,
    ) async {
      await _abrir(tester);

      expect(find.textContaining('Teléfono'), findsNothing);
      expect(find.textContaining('Enviar código'), findsNothing);
    });

    testWidgets('"Otro" cambia el alias por uno distinto', (tester) async {
      await _abrir(tester);
      final antes = _aliasActual(tester);

      await tester.tap(find.byKey(_otro));
      await tester.pump();

      expect(_aliasActual(tester), isNot(antes));
    });

    testWidgets('el alias se puede editar a mano', (tester) async {
      await _abrir(tester);

      await tester.enterText(find.byKey(_alias), 'Mi-Alias-1');

      expect(_aliasActual(tester), 'Mi-Alias-1');
    });

    testWidgets('"Volver" avisa', (tester) async {
      var volvio = false;
      await _abrir(tester, onBack: () => volvio = true);

      await tester.tap(find.text('Volver'));

      expect(volvio, isTrue);
    });
  });

  group('contraseña', () {
    testWidgets('empieza oculta y "Mostrar" la deja ver (y "Ocultar" no)', (
      tester,
    ) async {
      await _abrir(tester);
      bool oculta() =>
          tester.widget<TextField>(find.byKey(_password)).obscureText;

      expect(oculta(), isTrue);

      await tester.tap(find.byKey(_mostrar));
      await tester.pump();
      expect(oculta(), isFalse);
      expect(find.text('Ocultar'), findsOneWidget);

      await tester.tap(find.byKey(_mostrar));
      await tester.pump();
      expect(oculta(), isTrue);
    });

    testWidgets('el medidor sigue el largo: muy corta, aceptable, buena', (
      tester,
    ) async {
      await _abrir(tester);

      await tester.enterText(find.byKey(_password), 'abc');
      await tester.pump();
      expect(find.text('Muy corta'), findsOneWidget);

      await tester.enterText(find.byKey(_password), '123456789012');
      await tester.pump();
      expect(find.text('Aceptable'), findsOneWidget);

      await tester.enterText(find.byKey(_password), goodPassword);
      await tester.pump();
      expect(find.text('Buena'), findsOneWidget);
    });

    testWidgets('siempre recuerda el mínimo y sugiere una frase', (
      tester,
    ) async {
      await _abrir(tester);

      expect(
        find.textContaining(
          'Mín. 12 caracteres. Usa una frase fácil de recordar.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('pide al gestor de contraseñas que guarde alias y clave', (
      tester,
    ) async {
      await _abrir(tester);

      expect(
        tester.widget<TextField>(find.byKey(_alias)).autofillHints,
        contains(AutofillHints.newUsername),
      );
      expect(
        tester.widget<TextField>(find.byKey(_password)).autofillHints,
        contains(AutofillHints.newPassword),
      );
    });
  });

  group('crear la cuenta', () {
    testWidgets('sin aceptar la política no envía nada y lo explica', (
      tester,
    ) async {
      final repo = await _abrir(tester);
      await tester.enterText(find.byKey(_password), goodPassword);

      await _crearCuenta(tester);

      expect(repo.registerCalls, isEmpty);
      expect(find.textContaining('Debes aceptar'), findsOneWidget);
    });

    testWidgets('con contraseña de menos de 12 caracteres no envía nada', (
      tester,
    ) async {
      final repo = await _abrir(tester);
      await _llenarYMarcar(tester, password: 'corta123');

      await _crearCuenta(tester);

      expect(repo.registerCalls, isEmpty);
      expect(find.textContaining('al menos 12 caracteres'), findsOneWidget);
    });

    testWidgets('un alias con tilde o espacios no envía nada', (tester) async {
      final repo = await _abrir(tester);
      await _llenarYMarcar(tester);
      await tester.enterText(find.byKey(_alias), 'Cóndor Misti');

      await _crearCuenta(tester);

      expect(repo.registerCalls, isEmpty);
      expect(find.textContaining('sin tilde'), findsOneWidget);
    });

    testWidgets('con todo en regla envía alias, contraseña y consentimiento', (
      tester,
    ) async {
      final repo = await _abrir(tester);
      final alias = _aliasActual(tester);
      String? password;
      bool? consent;
      repo.onRegister = (a, p, c) async {
        password = p;
        consent = c;
        return testSession();
      };
      await _llenarYMarcar(tester);

      await _crearCuenta(tester);

      expect(repo.registerCalls, [alias]);
      expect(password, goodPassword);
      expect(consent, isTrue);
    });

    testWidgets(
      'mientras envía muestra progreso y un segundo toque no repite',
      (tester) async {
        final repo = await _abrir(tester);
        final espera = Completer<void>();
        repo.onRegister = (a, p, c) async {
          await espera.future;
          return testSession();
        };
        await _llenarYMarcar(tester);

        await _crearCuenta(tester);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        await tester.tap(find.byKey(_crear), warnIfMissed: false);
        await tester.pump();

        expect(repo.registerCalls, hasLength(1));
        espera.complete();
        await tester.pumpAndSettle();
      },
    );
  });

  group('cuando el servidor rechaza', () {
    testWidgets('alias ya en uso: el mensaje sale bajo el campo del alias', (
      tester,
    ) async {
      final repo = await _abrir(tester);
      repo.onRegister = (a, p, c) async => throw failure(
        'validation_failed',
        fields: {
          'alias': ['ya está en uso'],
        },
      );
      await _llenarYMarcar(tester);

      await _crearCuenta(tester);
      await tester.pump();

      expect(find.text('ya está en uso'), findsOneWidget);
    });

    testWidgets('error de la contraseña (p. ej. contiene el alias)', (
      tester,
    ) async {
      final repo = await _abrir(tester);
      repo.onRegister = (a, p, c) async => throw failure(
        'validation_failed',
        fields: {
          'password': ['no puede contener tu alias'],
        },
      );
      await _llenarYMarcar(tester);

      await _crearCuenta(tester);
      await tester.pump();

      expect(find.text('no puede contener tu alias'), findsOneWidget);
    });

    testWidgets('sin conexión: aviso propio y se puede reintentar', (
      tester,
    ) async {
      final repo = await _abrir(tester);
      repo.onRegister = (a, p, c) async => throw const ApiFailure.network();
      await _llenarYMarcar(tester);

      await _crearCuenta(tester);
      await tester.pump();

      expect(find.textContaining('Sin conexión'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byKey(_crear)).onPressed,
        isNotNull,
      );
    });

    testWidgets('límite de registros: cuenta regresiva y botón bloqueado hasta '
        'que termine', (tester) async {
      final repo = await _abrir(tester);
      repo.onRegister = (a, p, c) async =>
          throw failure('rate_limited', retryAfter: const Duration(seconds: 3));
      await _llenarYMarcar(tester);

      await _crearCuenta(tester);
      await tester.pump();

      expect(find.textContaining('0:03'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(_crear)).onPressed, isNull);

      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('0:02'), findsOneWidget);

      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(find.byKey(const Key('aviso-error-auth')), findsNothing);
      expect(
        tester.widget<FilledButton>(find.byKey(_crear)).onPressed,
        isNotNull,
      );
    });
  });
}
