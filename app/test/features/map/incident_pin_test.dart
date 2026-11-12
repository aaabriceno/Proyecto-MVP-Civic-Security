import 'package:civic_security/features/incident/domain/incident.dart';
import 'package:civic_security/features/map/presentation/incident_pin.dart';
import 'package:civic_security/features/map/presentation/incident_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

Incident _incident(IncidentStatus estado) => Incident(
  id: '00000000-0000-4000-8000-000000000001',
  tipo: IncidentType.robo,
  descripcion: null,
  position: const LatLng(-16.4, -71.5),
  estado: estado,
  creadoEn: DateTime.utc(2026, 11, 11),
);

Future<void> _pump(
  WidgetTester tester,
  IncidentStatus estado, {
  VoidCallback? onTap,
}) => tester.pumpWidget(
  MaterialApp(
    home: Center(
      child: IncidentPin(incident: _incident(estado), onTap: onTap ?? () {}),
    ),
  ),
);

/// El círculo de color del pin (el primer `Container` con decoración).
Color _colorDelPin(WidgetTester tester) {
  final container = tester.widget<Container>(
    find
        .descendant(
          of: find.byType(IncidentPin),
          matching: find.byType(Container),
        )
        .first,
  );
  return (container.decoration! as BoxDecoration).color!;
}

void main() {
  testWidgets('un pin sin verificar usa el color de su tipo', (tester) async {
    await _pump(tester, IncidentStatus.sinVerificar);

    expect(_colorDelPin(tester), typeColor(IncidentType.robo));
  });

  testWidgets('un pin verificado muestra la marca de verificado', (
    tester,
  ) async {
    await _pump(tester, IncidentStatus.verificado);

    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(_colorDelPin(tester), typeColor(IncidentType.robo));
  });

  testWidgets('un pin descartado se ve apagado: color más claro que su tipo', (
    tester,
  ) async {
    await _pump(tester, IncidentStatus.descartado);

    final normal = typeColor(IncidentType.robo);
    final apagado = _colorDelPin(tester);

    expect(apagado, isNot(normal));
    expect(
      apagado.computeLuminance(),
      greaterThan(normal.computeLuminance()),
      reason: 'apagado = más claro, para que no compita con los activos',
    );
    // Sigue siendo un color sólido: la transparencia haría ver el mapa a
    // través del pin y se confundiría con el borde
    expect(apagado.a, 1.0);
  });

  testWidgets('ningún pin usa Opacity (cada capa de transparencia cuesta mucho '
      'al dibujar y se multiplica por cada pin)', (tester) async {
    for (final estado in IncidentStatus.values) {
      await _pump(tester, estado);

      expect(
        find.descendant(
          of: find.byType(IncidentPin),
          matching: find.byType(Opacity),
        ),
        findsNothing,
        reason: 'estado: ${estado.label}',
      );
    }
  });

  testWidgets('tocar el pin avisa', (tester) async {
    var toques = 0;
    await _pump(tester, IncidentStatus.sinVerificar, onTap: () => toques++);

    await tester.tap(find.byType(IncidentPin));

    expect(toques, 1);
  });
}
