import 'package:civic_security/features/map/presentation/tile_health.dart';
import 'package:flutter_test/flutter_test.dart';

/// Como `testWidgets`, pero cierra el [TileHealth] al terminar el cuerpo: Flutter
/// revisa los temporizadores pendientes antes de correr los `addTearDown`.
void healthTest(
  String description,
  Future<void> Function(WidgetTester tester, TileHealth health) body, {
  TileHealth Function()? create,
}) {
  testWidgets(description, (tester) async {
    final health = (create ?? TileHealth.new)();
    try {
      await body(tester, health);
    } finally {
      health.dispose();
    }
  });
}

void main() {
  const window = Duration(seconds: 45);

  healthTest('empieza sin fallas', (tester, health) async {
    expect(health.failing, isFalse);
  });

  healthTest('uno o dos mosaicos caídos no son una falla del mapa', (
    tester,
    health,
  ) async {
    health
      ..report()
      ..report();

    expect(health.failing, isFalse);
  });

  healthTest('a partir del tercero sí lo es, y avisa a quien escucha', (
    tester,
    health,
  ) async {
    var avisos = 0;
    health.addListener(() => avisos++);

    health
      ..report()
      ..report();
    expect(avisos, 0, reason: 'todavía no cambia nada para la pantalla');
    health.report();

    expect(health.failing, isTrue);
    expect(avisos, 1);
  });

  healthTest('las fallas se olvidan pasado el tiempo', (tester, health) async {
    for (var i = 0; i < 5; i++) {
      health.report();
    }
    expect(health.failing, isTrue);

    await tester.pump(window - const Duration(seconds: 1));
    expect(health.failing, isTrue, reason: 'aún no pasa el tiempo');

    await tester.pump(const Duration(seconds: 2));
    expect(health.failing, isFalse);
  });

  healthTest('al dejar de fallar avisa una sola vez, no por cada falla vieja', (
    tester,
    health,
  ) async {
    for (var i = 0; i < 5; i++) {
      health.report();
    }
    var avisos = 0;
    health.addListener(() => avisos++);

    await tester.pump(window + const Duration(seconds: 1));

    expect(avisos, 1);
  });

  healthTest('cada falla se olvida a su hora, no todas juntas', (
    tester,
    health,
  ) async {
    health
      ..report()
      ..report();
    await tester.pump(const Duration(seconds: 30));
    health.report(); // la tercera, 30 s después de las dos primeras
    expect(health.failing, isTrue);

    // A los 46 s se olvidan las dos primeras; queda solo la tercera
    await tester.pump(const Duration(seconds: 16));

    expect(health.failing, isFalse);
  });

  healthTest('clear() borra las fallas y avisa', (tester, health) async {
    for (var i = 0; i < 4; i++) {
      health.report();
    }
    var avisos = 0;
    health.addListener(() => avisos++);

    health.clear();

    expect(health.failing, isFalse);
    expect(avisos, 1);

    // Lo anotado antes de borrar no debe restar después (el contador no queda
    // en negativo): tres fallas nuevas, y solo esas, vuelven a ser una falla
    await tester.pump(window + const Duration(seconds: 1));
    for (var i = 0; i < 3; i++) {
      health.report();
    }
    expect(health.failing, isTrue);
  });

  healthTest('clear() sin fallas no avisa a nadie', (tester, health) async {
    var avisos = 0;
    health.addListener(() => avisos++);

    health.clear();

    expect(avisos, 0);
  });

  testWidgets('tras cerrar la pantalla no queda nada pendiente ni falla', (
    tester,
  ) async {
    final health = TileHealth();
    for (var i = 0; i < 3; i++) {
      health.report();
    }

    health.dispose();
    // Un mosaico que falla justo cuando se cierra la pantalla tampoco debe romper
    health.report();
    health.dispose(); // y cerrar dos veces tampoco
    await tester.pump(window * 2);

    expect(tester.takeException(), isNull);
  });

  healthTest(
    'se puede configurar el umbral y el tiempo',
    (tester, health) async {
      health.report();
      expect(health.failing, isTrue);

      await tester.pump(const Duration(seconds: 6));
      expect(health.failing, isFalse);
    },
    create: () => TileHealth(threshold: 1, window: const Duration(seconds: 5)),
  );
}
