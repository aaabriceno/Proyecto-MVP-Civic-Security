import 'package:civic_security/features/map/presentation/tile_health.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Como `testWidgets`, pero cierra el [TileHealth] al terminar el cuerpo: Flutter
/// revisa los temporizadores pendientes antes de correr los `addTearDown`.
void bannerTest(
  String description,
  Future<void> Function(
    WidgetTester tester,
    TileHealth health,
    int Function() retries,
  )
  body,
) {
  testWidgets(description, (tester) async {
    final health = TileHealth();
    var retries = 0;
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TileErrorBanner(health: health, onRetry: () => retries++),
          ),
        ),
      );
      await body(tester, health, () => retries);
    } finally {
      health.dispose();
    }
  });
}

Future<void> _fail(WidgetTester tester, TileHealth health) async {
  for (var i = 0; i < 3; i++) {
    health.report();
  }
  await tester.pump();
}

void main() {
  bannerTest('sin fallas no muestra nada', (tester, health, _) async {
    expect(find.byKey(const Key('aviso-mosaicos')), findsNothing);
  });

  bannerTest(
    'con fallas dice que el mapa quedó incompleto y ofrece reintentar',
    (tester, health, _) async {
      await _fail(tester, health);

      final aviso = find.byKey(const Key('aviso-mosaicos'));
      expect(aviso, findsOneWidget);
      expect(
        find.descendant(
          of: aviso,
          matching: find.textContaining('Algunas partes del mapa no cargaron'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('boton-reintentar-mosaicos')),
        findsOneWidget,
      );
    },
  );

  bannerTest('"Reintentar" llama a onRetry', (tester, health, retries) async {
    await _fail(tester, health);

    await tester.tap(find.byKey(const Key('boton-reintentar-mosaicos')));

    expect(retries(), 1);
  });

  bannerTest('el aviso se va solo cuando las fallas se olvidan', (
    tester,
    health,
    _,
  ) async {
    await _fail(tester, health);
    expect(find.byKey(const Key('aviso-mosaicos')), findsOneWidget);

    await tester.pump(const Duration(minutes: 1));

    expect(find.byKey(const Key('aviso-mosaicos')), findsNothing);
  });

  bannerTest('un lector de pantalla lo anuncia al aparecer', (
    tester,
    health,
    _,
  ) async {
    await _fail(tester, health);

    final regionViva = find.descendant(
      of: find.byKey(const Key('aviso-mosaicos')),
      matching: find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.liveRegion == true,
      ),
    );

    expect(regionViva, findsOneWidget);
  });
}
