import 'dart:async';

import 'package:civic_security/core/network/api_failure.dart';
import 'package:civic_security/features/auth/presentation/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'auth_widget_harness.dart';
import 'fakes.dart';

const _alias = Key('campo-alias');
const _password = Key('campo-contrasena');
const _mostrar = Key('boton-mostrar-contrasena');
const _entrar = Key('boton-iniciar-sesion');

Future<FakeAuthRepository> _abrir(
  WidgetTester tester, {
  VoidCallback? onRegister,
  VoidCallback? onViewMap,
  VoidCallback? onForgotPassword,
}) async {
  final repo = FakeAuthRepository()..onLogout = (_) async {};
  await pumpAuth(
    tester,
    LoginScreen(
      onRegister: onRegister ?? () {},
      onViewMap: onViewMap ?? () {},
      onForgotPassword: onForgotPassword,
    ),
    repo: repo,
  );
  return repo;
}

Future<void> _escribir(
  WidgetTester tester, {
  String alias = 'Halcon-Misti-482',
  String password = goodPassword,
}) async {
  await tester.enterText(find.byKey(_alias), alias);
  await tester.enterText(find.byKey(_password), password);
  await tester.pump();
}

Future<void> _entrarYEsperar(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(_entrar));
  await tester.tap(find.byKey(_entrar));
  await tester.pump();
}

void main() {
  group('lo que se ve (frame 02)', () {
    testWidgets('título, subtítulo y los dos campos', (tester) async {
      await _abrir(tester);

      expect(find.text('Inicia sesión'), findsWidgets);
      expect(
        find.textContaining('Tu identidad nunca se muestra'),
        findsOneWidget,
      );
      expect(find.text('Alias'), findsOneWidget);
      expect(find.text('Contraseña'), findsOneWidget);
    });

    testWidgets('no ofrece teléfono, huella/passkey ni "reportar sin cuenta"', (
      tester,
    ) async {
      await _abrir(tester);

      expect(find.textContaining('teléfono'), findsNothing);
      expect(find.textContaining('passkey'), findsNothing);
      expect(find.textContaining('huella'), findsNothing);
      expect(find.textContaining('Reportar sin cuenta'), findsNothing);
    });

    testWidgets(
      '"¿Olvidaste tu contraseña?" solo aparece si hay recuperación',
      (tester) async {
        await _abrir(tester);
        expect(find.textContaining('Olvidaste'), findsNothing);

        var abrio = false;
        await _abrir(tester, onForgotPassword: () => abrio = true);
        await tester.tap(find.textContaining('Olvidaste'));

        expect(abrio, isTrue);
      },
    );

    testWidgets('"Ver el mapa sin cuenta" y "Regístrate" avisan', (
      tester,
    ) async {
      var mapa = false;
      var registro = false;
      await _abrir(
        tester,
        onViewMap: () => mapa = true,
        onRegister: () => registro = true,
      );

      await tester.ensureVisible(find.textContaining('Ver el mapa sin cuenta'));
      await tester.tap(find.textContaining('Ver el mapa sin cuenta'));
      await tester.ensureVisible(find.text('Regístrate'));
      await tester.tap(find.text('Regístrate'));

      expect(mapa, isTrue);
      expect(registro, isTrue);
    });

    testWidgets('la contraseña empieza oculta y "Mostrar" la deja ver', (
      tester,
    ) async {
      await _abrir(tester);
      bool oculta() =>
          tester.widget<TextField>(find.byKey(_password)).obscureText;

      expect(oculta(), isTrue);
      await tester.tap(find.byKey(_mostrar));
      await tester.pump();
      expect(oculta(), isFalse);
    });

    testWidgets('pide al gestor de contraseñas que rellene alias y clave', (
      tester,
    ) async {
      await _abrir(tester);

      expect(
        tester.widget<TextField>(find.byKey(_alias)).autofillHints,
        contains(AutofillHints.username),
      );
      expect(
        tester.widget<TextField>(find.byKey(_password)).autofillHints,
        contains(AutofillHints.password),
      );
    });
  });

  group('iniciar sesión', () {
    testWidgets('con los campos vacíos no envía nada y lo explica', (
      tester,
    ) async {
      final repo = await _abrir(tester);

      await _entrarYEsperar(tester);

      expect(repo.loginCalls, isEmpty);
      expect(find.text('Escribe tu alias.'), findsOneWidget);
      expect(find.text('Escribe tu contraseña.'), findsOneWidget);
    });

    testWidgets(
      'envía el alias sin espacios sobrantes y la contraseña tal cual',
      (tester) async {
        final repo = await _abrir(tester);
        String? password;
        repo.onLogin = (a, p) async {
          password = p;
          return testSession();
        };
        await _escribir(
          tester,
          alias: '  Halcon-Misti-482  ',
          password: ' mi clave ',
        );

        await _entrarYEsperar(tester);

        expect(repo.loginCalls, ['Halcon-Misti-482']);
        // La contraseña no se recorta: los espacios pueden ser parte de ella
        expect(password, ' mi clave ');
      },
    );

    testWidgets('mientras envía muestra progreso y no se puede repetir', (
      tester,
    ) async {
      final repo = await _abrir(tester);
      final espera = Completer<void>();
      repo.onLogin = (a, p) async {
        await espera.future;
        return testSession();
      };
      await _escribir(tester);

      await _entrarYEsperar(tester);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.byKey(_entrar), warnIfMissed: false);
      await tester.pump();

      expect(repo.loginCalls, hasLength(1));
      espera.complete();
      await tester.pumpAndSettle();
    });
  });

  group('cuando falla', () {
    testWidgets('credenciales incorrectas: un solo mensaje, sin decir cuál', (
      tester,
    ) async {
      final repo = await _abrir(tester);
      repo.onLogin = (a, p) async => throw failure('invalid_credentials');
      await _escribir(tester);

      await _entrarYEsperar(tester);
      await tester.pump();

      expect(find.text('Alias o contraseña incorrectos.'), findsOneWidget);
    });

    testWidgets('cuenta bloqueada: cuenta regresiva y botón bloqueado hasta '
        'que termine', (tester) async {
      final repo = await _abrir(tester);
      repo.onLogin = (a, p) async => throw failure(
        'account_locked',
        retryAfter: const Duration(seconds: 3),
      );
      await _escribir(tester);

      await _entrarYEsperar(tester);
      await tester.pump();

      expect(find.textContaining('Demasiados intentos'), findsOneWidget);
      expect(find.textContaining('0:03'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byKey(_entrar)).onPressed,
        isNull,
      );

      await tester.pump(const Duration(seconds: 3));
      await tester.pump();

      expect(find.byKey(const Key('aviso-error-auth')), findsNothing);
      expect(
        tester.widget<FilledButton>(find.byKey(_entrar)).onPressed,
        isNotNull,
      );
    });

    testWidgets('servidor ocupado y sin conexión tienen su propio aviso', (
      tester,
    ) async {
      final repo = await _abrir(tester);
      await _escribir(tester);

      repo.onLogin = (a, p) async => throw failure('server_busy');
      await _entrarYEsperar(tester);
      await tester.pump();
      expect(find.textContaining('ocupado'), findsOneWidget);

      repo.onLogin = (a, p) async => throw const ApiFailure.network();
      await _entrarYEsperar(tester);
      await tester.pump();
      expect(find.textContaining('Sin conexión'), findsOneWidget);
    });

    testWidgets('nunca muestra el texto crudo del servidor', (tester) async {
      final repo = await _abrir(tester);
      repo.onLogin = (a, p) async => throw failure('algo_raro');
      await _escribir(tester);

      await _entrarYEsperar(tester);
      await tester.pump();

      expect(find.textContaining('texto del servidor'), findsNothing);
    });
  });
}
