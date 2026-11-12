import 'dart:async';

import 'package:civic_security/core/network/api_failure.dart';
import 'package:civic_security/features/auth/domain/auth_models.dart';
import 'package:civic_security/features/auth/presentation/auth_controller.dart';
import 'package:civic_security/features/auth/presentation/auth_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'auth_widget_harness.dart';
import 'fakes.dart';

const _mapaConCuenta = Key('mapa-con-cuenta');
const _mapaPublico = Key('mapa-publico');

/// La puerta con dos mapas de mentira: lo que importa aquí es cuál se muestra.
Widget _gate({Duration offlineRetryEvery = const Duration(seconds: 30)}) =>
    AuthGate(
      offlineRetryEvery: offlineRetryEvery,
      signedInBuilder: (_) =>
          const Text('MAPA CON CUENTA', key: _mapaConCuenta),
      publicMapBuilder: (_, onSignIn) => Column(
        key: _mapaPublico,
        children: [
          const Text('MAPA PUBLICO'),
          TextButton(onPressed: onSignIn, child: const Text('Iniciar sesión')),
        ],
      ),
    );

Future<void> _tocar(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump();
}

/// El botón "atrás" del sistema Android.
Future<void> _atras(WidgetTester tester) async {
  final dynamic binding = tester.binding;
  await binding.handlePopRoute();
  await tester.pump();
}

void main() {
  group('al abrir la app', () {
    testWidgets('mientras recupera la sesión muestra la pantalla de carga', (
      tester,
    ) async {
      final repo = FakeAuthRepository();
      final espera = Completer<AuthTokens>();
      repo.onRefresh = (_) => espera.future;
      await pumpAuth(
        tester,
        _gate(),
        repo: repo,
        store: InMemoryTokenStore('refresh-guardado'),
      );

      expect(find.byKey(const Key('pantalla-cargando')), findsOneWidget);
      expect(find.text('Bienvenido a'), findsNothing);

      espera.completeError(const ApiFailure.network());
      await tester.pumpAndSettle();
    });

    testWidgets('sin sesión guardada muestra la bienvenida', (tester) async {
      await pumpAuth(tester, _gate());
      await tester.pump();

      expect(find.text('Bienvenido a'), findsOneWidget);
      expect(find.byKey(_mapaConCuenta), findsNothing);
    });

    testWidgets('con una sesión guardada válida entra directo al mapa', (
      tester,
    ) async {
      final repo = FakeAuthRepository()
        ..onRefresh = ((_) async => tokens('access-2', 'refresh-2'))
        ..onMe = ((_) async => testUser);
      await pumpAuth(
        tester,
        _gate(),
        repo: repo,
        store: InMemoryTokenStore('refresh-1'),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byKey(_mapaConCuenta), findsOneWidget);
      expect(find.text('Bienvenido a'), findsNothing);
    });

    testWidgets(
      'si el servidor ya no acepta la sesión, vuelve a la bienvenida',
      (tester) async {
        final repo = FakeAuthRepository()
          ..onLogout = ((_) async {})
          ..onRefresh = ((_) async => throw failure('invalid_token'));
        await pumpAuth(
          tester,
          _gate(),
          repo: repo,
          store: InMemoryTokenStore('refresh-vencido'),
        );
        await tester.pump();
        await tester.pump();

        expect(find.text('Bienvenido a'), findsOneWidget);
        expect(find.byKey(_mapaConCuenta), findsNothing);
      },
    );
  });

  group('sin señal al abrir', () {
    testWidgets('con sesión guardada deja entrar al mapa y reintenta después', (
      tester,
    ) async {
      final repo = FakeAuthRepository()
        ..onRefresh = ((_) async => throw const ApiFailure.network());
      await pumpAuth(
        tester,
        _gate(offlineRetryEvery: const Duration(seconds: 10)),
        repo: repo,
        store: InMemoryTokenStore('refresh-1'),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byKey(_mapaConCuenta), findsOneWidget);
      expect(repo.refreshCalls, hasLength(1));

      // Vuelve la señal: el siguiente intento confirma la sesión
      repo
        ..onRefresh = ((_) async => tokens('access-2', 'refresh-2'))
        ..onMe = ((_) async => testUser);
      await tester.pump(const Duration(seconds: 10));
      await tester.pump();

      expect(repo.refreshCalls, hasLength(2));
      expect(find.byKey(_mapaConCuenta), findsOneWidget);
    });

    testWidgets('una vez confirmada la sesión deja de reintentar', (
      tester,
    ) async {
      final repo = FakeAuthRepository()
        ..onRefresh = ((_) async => throw const ApiFailure.network());
      await pumpAuth(
        tester,
        _gate(offlineRetryEvery: const Duration(seconds: 10)),
        repo: repo,
        store: InMemoryTokenStore('refresh-1'),
      );
      await tester.pump();
      await tester.pump();
      expect(repo.refreshCalls, hasLength(1));

      // Vuelve la señal: el reintento confirma la sesión
      repo
        ..onRefresh = ((_) async => tokens('access-2', 'refresh-2'))
        ..onMe = ((_) async => testUser);
      await tester.pump(const Duration(seconds: 10));
      await tester.pump();
      expect(repo.refreshCalls, hasLength(2));
      expect(repo.meCalls, hasLength(1));

      // Con la sesión confirmada, el tiempo pasa y no hay más llamadas. Se
      // cuenta `me` porque, con el access token vigente, un reintento ya no
      // necesita renovarlo: solo volvería a pedir la cuenta.
      await tester.pump(const Duration(seconds: 60));
      expect(repo.refreshCalls, hasLength(2));
      expect(repo.meCalls, hasLength(1));
    });
  });

  group('sin sesión: bienvenida, login y registro', () {
    testWidgets('Comenzar lleva al login; Regístrate, al registro', (
      tester,
    ) async {
      await pumpAuth(tester, _gate());
      await tester.pump();

      await _tocar(tester, find.text('Comenzar'));
      expect(find.text('Iniciar sesión'), findsOneWidget);

      await _tocar(tester, find.text('Regístrate'));
      expect(find.text('Crea tu cuenta anónima'), findsOneWidget);
    });

    testWidgets('"Volver" y el botón atrás del sistema retroceden un paso', (
      tester,
    ) async {
      await pumpAuth(tester, _gate());
      await tester.pump();
      await _tocar(tester, find.text('Comenzar'));
      await _tocar(tester, find.text('Regístrate'));

      await _tocar(tester, find.text('Volver'));
      expect(find.text('Iniciar sesión'), findsOneWidget);

      await _tocar(tester, find.text('Regístrate'));
      await _atras(tester);
      expect(find.text('Iniciar sesión'), findsOneWidget);

      await _atras(tester);
      expect(find.text('Bienvenido a'), findsOneWidget);
    });

    testWidgets('"Ver el mapa sin cuenta" muestra el mapa público y se puede '
        'volver a iniciar sesión', (tester) async {
      await pumpAuth(tester, _gate());
      await tester.pump();
      await _tocar(tester, find.text('Comenzar'));

      await _tocar(tester, find.byKey(const Key('boton-ver-mapa')));
      expect(find.byKey(_mapaPublico), findsOneWidget);
      expect(find.byKey(_mapaConCuenta), findsNothing);

      await _tocar(tester, find.text('Iniciar sesión'));
      expect(find.byKey(const Key('boton-iniciar-sesion')), findsOneWidget);
    });

    testWidgets('el error de un intento no se arrastra a la otra pantalla', (
      tester,
    ) async {
      final repo = FakeAuthRepository()
        ..onLogin = ((a, p) async => throw failure('invalid_credentials'));
      await pumpAuth(tester, _gate(), repo: repo);
      await tester.pump();
      await _tocar(tester, find.text('Comenzar'));
      await tester.enterText(find.byKey(const Key('campo-alias')), 'Alguien');
      await tester.enterText(
        find.byKey(const Key('campo-contrasena')),
        goodPassword,
      );
      await _tocar(tester, find.byKey(const Key('boton-iniciar-sesion')));
      await tester.pump();
      expect(find.text('Alias o contraseña incorrectos.'), findsOneWidget);

      await _tocar(tester, find.text('Regístrate'));

      expect(find.byKey(const Key('aviso-error-auth')), findsNothing);
    });
  });

  group('de punta a punta', () {
    testWidgets('registrarse deja entrar al mapa y guarda la sesión', (
      tester,
    ) async {
      final store = InMemoryTokenStore();
      final repo = FakeAuthRepository()
        ..onRegister = ((a, p, c) async => testSession());
      await pumpAuth(tester, _gate(), repo: repo, store: store);
      await tester.pump();
      await _tocar(tester, find.text('Comenzar'));
      await _tocar(tester, find.text('Regístrate'));

      await tester.enterText(
        find.byKey(const Key('campo-contrasena')),
        goodPassword,
      );
      await _tocar(tester, find.byKey(const Key('checkbox-consentimiento')));
      await _tocar(tester, find.byKey(const Key('boton-crear-cuenta')));
      await tester.pump();
      await tester.pump();

      expect(find.byKey(_mapaConCuenta), findsOneWidget);
      expect(find.text('Crea tu cuenta anónima'), findsNothing);
      expect(store.value, 'refresh-1');
    });

    testWidgets('cerrar sesión devuelve a la bienvenida', (tester) async {
      final repo = FakeAuthRepository()
        ..onLogout = ((_) async {})
        ..onRefresh = ((_) async => tokens('access-2', 'refresh-2'))
        ..onMe = ((_) async => testUser);
      final container = await pumpAuth(
        tester,
        _gate(),
        repo: repo,
        store: InMemoryTokenStore('refresh-1'),
      );
      await tester.pump();
      await tester.pump();
      expect(find.byKey(_mapaConCuenta), findsOneWidget);

      await container.read(authControllerProvider.notifier).logout();
      await tester.pump();

      expect(find.text('Bienvenido a'), findsOneWidget);
      expect(find.byKey(_mapaConCuenta), findsNothing);
    });
  });
}
