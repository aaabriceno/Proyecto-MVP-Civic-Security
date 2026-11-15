import 'package:civic_security/features/profile/presentation/delete_account_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../auth/auth_widget_harness.dart' show failure;
import '../auth/fakes.dart';
import 'profile_harness.dart';

const _clave = 'mi contraseña de ahora';

FakeAuthRepository _repoOk() => FakeAuthRepository()
  ..onDeleteAccount = ((_, _) async {})
  ..onLogout = ((_) async {});

Future<void> _escribe(WidgetTester tester, String password) async {
  await tester.enterText(find.byKey(const Key('campo-contrasena')), password);
  await tester.pump();
}

Future<void> _entiendo(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('checkbox-entiendo')));
  await tester.pump();
}

Future<void> _borrar(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('boton-borrar-cuenta')));
  await tester.pumpAndSettle();
}

bool _habilitado(WidgetTester tester) =>
    tester
        .widget<FilledButton>(find.byKey(const Key('boton-borrar-cuenta')))
        .onPressed !=
    null;

void main() {
  testWidgets('explica qué se borra y qué se conserva', (tester) async {
    await pumpProfile(tester, const DeleteAccountScreen(), repo: _repoOk());

    expect(find.textContaining('Esto no se puede deshacer'), findsOneWidget);
    expect(
      find.textContaining('Tus reportes seguirán en el mapa'),
      findsOneWidget,
    );
    expect(find.textContaining('sin ningún vínculo contigo'), findsOneWidget);
  });

  testWidgets(
    'el botón está apagado hasta marcar la casilla y escribir la contraseña',
    (tester) async {
      await pumpProfile(tester, const DeleteAccountScreen(), repo: _repoOk());
      expect(_habilitado(tester), isFalse);

      await _escribe(tester, _clave);
      expect(_habilitado(tester), isFalse, reason: 'falta la casilla');

      await _entiendo(tester);
      expect(_habilitado(tester), isTrue);

      await _escribe(tester, '');
      expect(_habilitado(tester), isFalse, reason: 'se borró la contraseña');
    },
  );

  testWidgets('la contraseña empieza oculta', (tester) async {
    await pumpProfile(tester, const DeleteAccountScreen(), repo: _repoOk());

    expect(
      tester
          .widget<TextField>(find.byKey(const Key('campo-contrasena')))
          .obscureText,
      isTrue,
    );
  });

  testWidgets(
    'al borrar manda la contraseña y cierra la sesión de este teléfono',
    (tester) async {
      final h = await pumpProfile(
        tester,
        const DeleteAccountScreen(),
        repo: _repoOk(),
      );
      await _escribe(tester, _clave);
      await _entiendo(tester);

      await _borrar(tester);

      expect(h.repo.deleteAccountCalls, [_clave]);
      expect(h.auth.logouts, 1);
      expect(
        find.byType(DeleteAccountScreen),
        findsNothing,
        reason: 'sale de la pantalla',
      );
    },
  );

  testWidgets(
    'con una contraseña incorrecta lo dice en el campo y NO cierra la sesión',
    (tester) async {
      final repo = FakeAuthRepository()
        ..onDeleteAccount = ((_, _) async => throw failure(
          'validation_failed',
          fields: {
            'password': ['es incorrecta'],
          },
        ));
      final h = await pumpProfile(
        tester,
        const DeleteAccountScreen(),
        repo: repo,
      );
      await _escribe(tester, 'otra distinta larga');
      await _entiendo(tester);

      await _borrar(tester);

      expect(find.text('La contraseña no es correcta.'), findsOneWidget);
      expect(h.auth.logouts, 0);
      expect(find.byType(DeleteAccountScreen), findsOneWidget);
    },
  );

  testWidgets(
    'una cuenta bloqueada muestra la cuenta regresiva y no deja reintentar',
    (tester) async {
      final repo = FakeAuthRepository()
        ..onDeleteAccount = ((_, _) async => throw failure(
          'account_locked',
          retryAfter: const Duration(seconds: 30),
        ));
      await pumpProfile(tester, const DeleteAccountScreen(), repo: repo);
      await _escribe(tester, _clave);
      await _entiendo(tester);

      await _borrar(tester);

      expect(find.byKey(const Key('aviso-error-auth')), findsOneWidget);
      expect(find.textContaining('0:30'), findsOneWidget);
      expect(_habilitado(tester), isFalse);
    },
  );

  testWidgets('sin conexión avisa y no cierra la sesión', (tester) async {
    final repo = FakeAuthRepository()
      ..onDeleteAccount = ((_, _) async => throw failure('network'));
    final h = await pumpProfile(
      tester,
      const DeleteAccountScreen(),
      repo: repo,
    );
    await _escribe(tester, _clave);
    await _entiendo(tester);

    await _borrar(tester);

    expect(find.textContaining('Sin conexión'), findsOneWidget);
    expect(h.auth.logouts, 0);
  });

  testWidgets('"Cancelar" vuelve sin tocar nada', (tester) async {
    final h = await pumpProfile(
      tester,
      const DeleteAccountScreen(),
      repo: _repoOk(),
    );

    await tester.tap(find.byKey(const Key('boton-cancelar-borrado')));
    await tester.pumpAndSettle();

    expect(find.byType(DeleteAccountScreen), findsNothing);
    expect(h.repo.deleteAccountCalls, isEmpty);
    expect(h.auth.logouts, 0);
  });

  testWidgets('no se puede enviar dos veces mientras espera', (tester) async {
    final repo = FakeAuthRepository()
      ..onDeleteAccount = ((_, _) =>
          Future<void>.delayed(const Duration(seconds: 1)))
      ..onLogout = ((_) async {});
    await pumpProfile(tester, const DeleteAccountScreen(), repo: repo);
    await _escribe(tester, _clave);
    await _entiendo(tester);

    await tester.tap(find.byKey(const Key('boton-borrar-cuenta')));
    await tester.pump();
    await tester.tap(
      find.byKey(const Key('boton-borrar-cuenta')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(repo.deleteAccountCalls, hasLength(1));
  });
}
