import 'dart:async';

import 'package:civic_security/features/auth/domain/auth_models.dart';
import 'package:civic_security/features/profile/presentation/change_password_screen.dart';
import 'package:civic_security/features/profile/presentation/delete_account_screen.dart';
import 'package:civic_security/features/profile/presentation/profile_screen.dart';
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
  cupo: ReportQuota(usados: 4, maximo: 10),
);

void main() {
  testWidgets(
    'muestra el alias, las iniciales y desde cuándo existe la cuenta',
    (tester) async {
      await pumpProfile(tester, const ProfileScreen());

      expect(find.byKey(const Key('perfil-alias')), findsOneWidget);
      expect(find.text('Halcon-Misti-482'), findsOneWidget);
      expect(find.byKey(const Key('perfil-iniciales')), findsOneWidget);
      expect(find.text('HM'), findsOneWidget);
      expect(find.text('Alias público · desde sep. 2026'), findsOneWidget);
    },
  );

  testWidgets('una cuenta sin verificar lo dice', (tester) async {
    await pumpProfile(tester, const ProfileScreen());

    expect(find.byKey(const Key('perfil-nivel')), findsOneWidget);
    expect(find.text('Cuenta sin verificar'), findsOneWidget);
    expect(find.text('Cuenta verificada'), findsNothing);
  });

  testWidgets('una cuenta verificada lo dice, con su cupo mayor', (
    tester,
  ) async {
    await pumpProfile(tester, const ProfileScreen(), user: _verificada);

    expect(find.text('Cuenta verificada'), findsOneWidget);
    expect(find.text('Cuenta sin verificar'), findsNothing);
    expect(find.text('4 de 10'), findsOneWidget);
  });

  testWidgets('muestra cuántos reportes lleva hoy del cupo', (tester) async {
    await pumpProfile(tester, const ProfileScreen());

    expect(find.byKey(const Key('perfil-cupo')), findsOneWidget);
    expect(find.text('1 de 3'), findsOneWidget);
    expect(find.text('Reportes de hoy'), findsOneWidget);
  });

  testWidgets('sin cupo conocido no inventa un número', (tester) async {
    await pumpProfile(
      tester,
      const ProfileScreen(),
      user: const AuthUser(
        id: 'x',
        alias: 'Yo-Mismo',
        nivel: AuthLevel.invitado,
      ),
    );

    expect(find.byKey(const Key('perfil-cupo')), findsOneWidget);
    final numero = RegExp(r'^\d+ de \d+$');
    expect(
      find.byWidgetPredicate((w) => w is Text && numero.hasMatch(w.data ?? '')),
      findsNothing,
    );
  });

  testWidgets('aclara que el historial es privado', (tester) async {
    await pumpProfile(tester, const ProfileScreen());

    expect(
      find.textContaining('no guarda qué reportes son tuyos'),
      findsOneWidget,
    );
  });

  testWidgets('"Cambiar contraseña" abre su pantalla', (tester) async {
    await pumpProfile(tester, const ProfileScreen());

    await tester.tap(find.byKey(const Key('fila-cambiar-contrasena')));
    await tester.pumpAndSettle();

    expect(find.byType(ChangePasswordScreen), findsOneWidget);
  });

  testWidgets('"Borrar mi cuenta" abre su pantalla', (tester) async {
    await pumpProfile(tester, const ProfileScreen());
    await tester.ensureVisible(find.byKey(const Key('fila-borrar-cuenta')));

    await tester.tap(find.byKey(const Key('fila-borrar-cuenta')));
    await tester.pumpAndSettle();

    expect(find.byType(DeleteAccountScreen), findsOneWidget);
  });

  testWidgets('"Qué guardamos de ti" dice qué se guarda y qué no', (
    tester,
  ) async {
    await pumpProfile(tester, const ProfileScreen());
    await tester.ensureVisible(find.byKey(const Key('fila-que-guardamos')));

    await tester.tap(find.byKey(const Key('fila-que-guardamos')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('hoja-que-guardamos')), findsOneWidget);
    expect(find.textContaining('Tu alias'), findsOneWidget);
    expect(find.textContaining('nunca tu contraseña'), findsOneWidget);
    expect(
      find.textContaining('Tu nombre, tu correo, tu teléfono ni tu IP'),
      findsOneWidget,
    );
    expect(find.textContaining('quién hizo cada reporte'), findsOneWidget);
  });

  testWidgets('"Cerrar sesión" cierra la sesión y deja la pantalla', (
    tester,
  ) async {
    final h = await pumpProfile(tester, const ProfileScreen());
    await tester.ensureVisible(find.byKey(const Key('boton-cerrar-sesion')));

    await tester.tap(find.byKey(const Key('boton-cerrar-sesion')));
    await tester.pumpAndSettle();

    expect(h.auth.logouts, 1);
    expect(find.byType(ProfileScreen), findsNothing);
  });

  testWidgets(
    '"Cerrar sesión" vuelve hasta la primera pantalla, aunque haya otras encima',
    (tester) async {
      // Como en la app: la puerta de entrada, el mapa encima y el perfil sobre
      // el mapa. Al cerrar sesión no puede quedar el mapa con la cuenta cerrada.
      final h = await pumpProfile(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              ),
              child: const Text('ir al perfil'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('ir al perfil'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('boton-cerrar-sesion')));

      await tester.tap(find.byKey(const Key('boton-cerrar-sesion')));
      await tester.pumpAndSettle();

      expect(h.auth.logouts, 1);
      expect(
        find.text('ir al perfil'),
        findsNothing,
        reason: 'el mapa también se fue',
      );
      expect(
        find.text('abrir'),
        findsOneWidget,
        reason: 'se volvió a la primera',
      );
    },
  );

  testWidgets('el botón de atrás vuelve sin cerrar la sesión', (tester) async {
    final h = await pumpProfile(tester, const ProfileScreen());

    await tester.tap(find.byKey(const Key('boton-volver-perfil')));
    await tester.pumpAndSettle();

    expect(find.byType(ProfileScreen), findsNothing);
    expect(h.auth.logouts, 0);
  });

  group('si no se puede cargar el perfil', () {
    testWidgets('avisa, permite reintentar y sigue ofreciendo cerrar sesión', (
      tester,
    ) async {
      final repo = FakeAuthRepository()
        ..onMe = ((_) async => throw failure('network'))
        ..onLogout = ((_) async {});
      await pumpProfile(tester, const ProfileScreen(), repo: repo);

      expect(find.byKey(const Key('aviso-perfil')), findsOneWidget);
      expect(find.byKey(const Key('reintentar-perfil')), findsOneWidget);
      expect(find.byKey(const Key('boton-cerrar-sesion')), findsOneWidget);
    });

    testWidgets('Reintentar vuelve a pedirlo y lo muestra', (tester) async {
      var intentos = 0;
      final repo = FakeAuthRepository()
        ..onMe = ((_) async {
          intentos++;
          if (intentos == 1) throw failure('network');
          return profileUser;
        })
        ..onLogout = ((_) async {});
      await pumpProfile(tester, const ProfileScreen(), repo: repo);

      await tester.tap(find.byKey(const Key('reintentar-perfil')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('aviso-perfil')), findsNothing);
      expect(find.text('Halcon-Misti-482'), findsOneWidget);
    });
  });

  testWidgets('mientras carga muestra un indicador', (tester) async {
    final completer = Completer<AuthUser>();
    final repo = FakeAuthRepository()
      ..onMe = ((_) => completer.future)
      ..onLogout = ((_) async {});
    await pumpProfile(tester, const ProfileScreen(), repo: repo, settle: false);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    completer.complete(profileUser);
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Halcon-Misti-482'), findsOneWidget);
  });

  group('verificar con el DNI', () {
    testWidgets('una cuenta sin verificar ofrece verificarse', (tester) async {
      await pumpProfile(tester, const ProfileScreen());

      final tarjeta = find.byKey(const Key('perfil-verificar'));
      expect(tarjeta, findsOneWidget);
      expect(
        find.descendant(
          of: tarjeta,
          matching: find.textContaining('Verifica tu DNI'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('una cuenta verificada no ofrece nada', (tester) async {
      await pumpProfile(tester, const ProfileScreen(), user: _verificada);

      expect(find.byKey(const Key('perfil-verificar')), findsNothing);
    });

    testWidgets('mientras carga el perfil tampoco la ofrece', (tester) async {
      final repo = FakeAuthRepository()
        ..onMe = ((_) => Completer<AuthUser>().future)
        ..onLogout = ((_) async {});
      await pumpProfile(
        tester,
        const ProfileScreen(),
        repo: repo,
        settle: false,
      );

      expect(find.byKey(const Key('perfil-verificar')), findsNothing);
    });

    testWidgets('al tocarla abre la pantalla del DNI', (tester) async {
      await pumpProfile(tester, const ProfileScreen());

      await tester.tap(find.byKey(const Key('perfil-verificar')));
      await tester.pumpAndSettle();

      expect(find.byType(VerifyDniScreen), findsOneWidget);
    });

    testWidgets('al verificarse, el perfil se actualiza solo', (tester) async {
      var verificada = false;
      final repo = FakeAuthRepository()
        ..onMe = ((_) async => verificada ? _verificada : profileUser)
        ..onVerifyDni = ((_, _) async {
          verificada = true;
          return _verificada;
        });
      await pumpProfile(tester, const ProfileScreen(), repo: repo);
      await tester.tap(find.byKey(const Key('perfil-verificar')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('campo-dni')), '12345678');
      await tester.pump();

      await tester.tap(find.byKey(const Key('boton-verificar-dni')));
      await tester.pumpAndSettle();

      expect(find.byType(VerifyDniScreen), findsNothing);
      expect(find.text('Cuenta verificada'), findsOneWidget);
      expect(find.text('Cuenta sin verificar'), findsNothing);
      expect(find.byKey(const Key('perfil-verificar')), findsNothing);
      expect(find.text('4 de 10'), findsOneWidget);
    });

    testWidgets('si se vuelve sin verificar, no vuelve a pedir el perfil', (
      tester,
    ) async {
      final repo = FakeAuthRepository()
        ..onMe = ((_) async => profileUser)
        ..onLogout = ((_) async {});
      await pumpProfile(tester, const ProfileScreen(), repo: repo);
      await tester.tap(find.byKey(const Key('perfil-verificar')));
      await tester.pumpAndSettle();

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.byType(VerifyDniScreen), findsNothing);
      expect(repo.meCalls, hasLength(1));
    });
  });
}
