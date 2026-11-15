import 'package:civic_security/features/auth/domain/auth_models.dart';
import 'package:civic_security/features/profile/presentation/change_password_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../auth/auth_widget_harness.dart' show failure;
import '../auth/fakes.dart';
import 'profile_harness.dart';

const _actual = 'mi contraseña de ahora';
const _nueva = 'una frase nueva y larga';

Future<void> _escribe(WidgetTester tester, String actual, String nueva) async {
  await tester.enterText(
    find.byKey(const Key('campo-contrasena-actual')),
    actual,
  );
  await tester.enterText(
    find.byKey(const Key('campo-contrasena-nueva')),
    nueva,
  );
  await tester.pump();
}

Future<void> _enviar(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('boton-cambiar-contrasena')));
  await tester.pumpAndSettle();
}

FakeAuthRepository _repoOk() => FakeAuthRepository()
  ..onChangePassword = ((_, _, _) async =>
      AuthSession(user: profileUser, tokens: tokens('access-2', 'refresh-2')));

void main() {
  testWidgets('pide la contraseña actual y la nueva, con el medidor', (
    tester,
  ) async {
    await pumpProfile(tester, const ChangePasswordScreen(), repo: _repoOk());

    expect(find.byKey(const Key('campo-contrasena-actual')), findsOneWidget);
    expect(find.byKey(const Key('campo-contrasena-nueva')), findsOneWidget);
    expect(find.byKey(const Key('medidor-contrasena')), findsOneWidget);
    expect(find.byKey(const Key('boton-cambiar-contrasena')), findsOneWidget);
  });

  testWidgets('en una pantalla alta el formulario empieza arriba, no centrado', (
    tester,
  ) async {
    await pumpProfile(tester, const ChangePasswordScreen(), repo: _repoOk());

    final arriba = tester
        .getTopLeft(find.byKey(const Key('campo-contrasena-actual')))
        .dy;

    // La pantalla de la prueba mide 1600 de alto: centrado quedaría pasando 500
    expect(arriba, lessThan(300));
  });

  testWidgets('las contraseñas empiezan ocultas y "Mostrar" las descubre', (
    tester,
  ) async {
    await pumpProfile(tester, const ChangePasswordScreen(), repo: _repoOk());
    bool oculta(String k) =>
        tester.widget<TextField>(find.byKey(Key(k))).obscureText;

    expect(oculta('campo-contrasena-actual'), isTrue);
    expect(oculta('campo-contrasena-nueva'), isTrue);

    await tester.tap(find.byKey(const Key('boton-mostrar-contrasenas')));
    await tester.pump();

    expect(oculta('campo-contrasena-actual'), isFalse);
    expect(oculta('campo-contrasena-nueva'), isFalse);
  });

  group('validación en el teléfono (sin molestar al servidor)', () {
    testWidgets('sin la actual', (tester) async {
      final h = await pumpProfile(
        tester,
        const ChangePasswordScreen(),
        repo: _repoOk(),
      );
      await _escribe(tester, '', _nueva);

      await _enviar(tester);

      expect(find.text('Escribe tu contraseña actual.'), findsOneWidget);
      expect(h.repo.changePasswordCalls, isEmpty);
    });

    testWidgets('una nueva de menos de 12 caracteres', (tester) async {
      final h = await pumpProfile(
        tester,
        const ChangePasswordScreen(),
        repo: _repoOk(),
      );
      await _escribe(tester, _actual, 'corta');

      await _enviar(tester);

      expect(find.textContaining('al menos 12'), findsWidgets);
      expect(h.repo.changePasswordCalls, isEmpty);
    });

    testWidgets('una nueva igual a la actual', (tester) async {
      final h = await pumpProfile(
        tester,
        const ChangePasswordScreen(),
        repo: _repoOk(),
      );
      await _escribe(tester, _actual, _actual);

      await _enviar(tester);

      expect(
        find.text('La nueva debe ser distinta de la actual.'),
        findsOneWidget,
      );
      expect(h.repo.changePasswordCalls, isEmpty);
    });
  });

  testWidgets('envía las dos contraseñas y, si sale bien, vuelve avisando', (
    tester,
  ) async {
    final h = await pumpProfile(
      tester,
      const ChangePasswordScreen(),
      repo: _repoOk(),
    );
    await _escribe(tester, _actual, _nueva);

    await _enviar(tester);

    expect(h.repo.changePasswordCalls, [(current: _actual, next: _nueva)]);
    expect(find.byType(ChangePasswordScreen), findsNothing);
    expect(
      find.text('Contraseña cambiada. Cerramos tus otras sesiones.'),
      findsOneWidget,
    );
  });

  testWidgets('guarda la sesión nueva', (tester) async {
    final h = await pumpProfile(
      tester,
      const ChangePasswordScreen(),
      repo: _repoOk(),
    );
    await _escribe(tester, _actual, _nueva);

    await _enviar(tester);

    expect(h.store.value, 'refresh-2');
  });

  testWidgets('la contraseña actual incorrecta se marca en su campo', (
    tester,
  ) async {
    final repo = FakeAuthRepository()
      ..onChangePassword = ((_, _, _) async => throw failure(
        'validation_failed',
        fields: {
          'current_password': ['es incorrecta'],
        },
      ));
    await pumpProfile(tester, const ChangePasswordScreen(), repo: repo);
    await _escribe(tester, 'otra distinta larga', _nueva);

    await _enviar(tester);

    expect(find.text('La contraseña actual no es correcta.'), findsOneWidget);
    expect(
      find.byType(ChangePasswordScreen),
      findsOneWidget,
      reason: 'sigue abierta',
    );
  });

  testWidgets('una nueva rechazada por el servidor muestra por qué', (
    tester,
  ) async {
    final repo = FakeAuthRepository()
      ..onChangePassword = ((_, _, _) async => throw failure(
        'validation_failed',
        fields: {
          'new_password': ['es demasiado simple'],
        },
      ));
    await pumpProfile(tester, const ChangePasswordScreen(), repo: repo);
    await _escribe(tester, _actual, _nueva);

    await _enviar(tester);

    expect(
      find.text('La contraseña nueva es demasiado simple.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'una cuenta bloqueada muestra la cuenta regresiva y no deja reintentar',
    (tester) async {
      final repo = FakeAuthRepository()
        ..onChangePassword = ((_, _, _) async => throw failure(
          'account_locked',
          retryAfter: const Duration(seconds: 45),
        ));
      await pumpProfile(tester, const ChangePasswordScreen(), repo: repo);
      await _escribe(tester, _actual, _nueva);

      await _enviar(tester);

      expect(find.byKey(const Key('aviso-error-auth')), findsOneWidget);
      expect(find.textContaining('0:45'), findsOneWidget);
      final boton = tester.widget<FilledButton>(
        find.byKey(const Key('boton-cambiar-contrasena')),
      );
      expect(boton.onPressed, isNull);
    },
  );

  testWidgets('sin conexión avisa, sin mostrar el texto del servidor', (
    tester,
  ) async {
    final repo = FakeAuthRepository()
      ..onChangePassword = ((_, _, _) async => throw failure('network'));
    await pumpProfile(tester, const ChangePasswordScreen(), repo: repo);
    await _escribe(tester, _actual, _nueva);

    await _enviar(tester);

    expect(find.textContaining('Sin conexión'), findsOneWidget);
    expect(find.text('texto del servidor'), findsNothing);
  });

  testWidgets('mientras envía, el botón no deja enviar dos veces', (
    tester,
  ) async {
    final repo = FakeAuthRepository();
    final pendiente = <Future<AuthSession>>[];
    repo.onChangePassword = (_, _, _) {
      final f = Future<AuthSession>.delayed(
        const Duration(seconds: 1),
        () => AuthSession(user: profileUser, tokens: tokens('a2', 'r2')),
      );
      pendiente.add(f);
      return f;
    };
    await pumpProfile(tester, const ChangePasswordScreen(), repo: repo);
    await _escribe(tester, _actual, _nueva);

    await tester.tap(find.byKey(const Key('boton-cambiar-contrasena')));
    await tester.pump();
    await tester.tap(
      find.byKey(const Key('boton-cambiar-contrasena')),
      warnIfMissed: false,
    );
    await tester.pump();
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(repo.changePasswordCalls, hasLength(1));
  });
}
