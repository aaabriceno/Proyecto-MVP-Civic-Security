import 'package:civic_security/features/auth/presentation/welcome_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'auth_widget_harness.dart';

Future<void> _abrir(WidgetTester tester, {VoidCallback? onStart}) =>
    pumpAuth(tester, WelcomeScreen(onStart: onStart ?? () {}));

void main() {
  testWidgets('da la bienvenida con el texto del diseño, ya sin las erratas', (
    tester,
  ) async {
    await _abrir(tester);

    expect(find.text('Bienvenido a'), findsOneWidget);
    expect(find.text('CIVIC SECURITY'), findsOneWidget);
    expect(
      find.text(
        'Esta es una aplicación enfocada en el apoyo entre ciudadanos para '
        'mantener a la población alerta.',
      ),
      findsOneWidget,
    );
    // El diseño decía "manter" y "poblacion"
    expect(find.textContaining('manter '), findsNothing);
    expect(find.textContaining('poblacion'), findsNothing);
  });

  testWidgets('"Comenzar" avisa', (tester) async {
    var comenzo = false;
    await _abrir(tester, onStart: () => comenzo = true);

    await tester.tap(find.text('Comenzar'));

    expect(comenzo, isTrue);
  });

  testWidgets('muestra una ilustración propia (no una captura de otro mapa)', (
    tester,
  ) async {
    await _abrir(tester);

    // Dibujada en código: no hay imágenes ni capturas de Google Maps
    expect(find.byKey(const Key('ilustracion-bienvenida')), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('en una pantalla baja y con letra grande no se desborda', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 560);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(MaterialApp(home: WelcomeScreen(onStart: () {})));

    expect(tester.takeException(), isNull);
    expect(find.text('Comenzar'), findsOneWidget);
  });
}
