import 'package:civic_security/core/phone/dialer.dart';
import 'package:civic_security/features/incident/domain/incident.dart';
import 'package:civic_security/features/report/presentation/report_sent_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

class _FakeDialer implements Dialer {
  final dialed = <String>[];

  @override
  Future<void> dial(String number) async => dialed.add(number);
}

final _incident = Incident(
  id: 'x',
  tipo: IncidentType.robo,
  descripcion: null,
  position: const LatLng(-16.4, -71.5),
  estado: IncidentStatus.sinVerificar,
  creadoEn: DateTime.utc(2026, 11, 4),
);

/// Abre la pantalla desde un botón para poder leer con qué se cierra.
Future<({_FakeDialer dialer, Future<bool?> Function() opened})> _pump(
  WidgetTester tester,
) async {
  final dialer = _FakeDialer();
  Future<bool?>? result;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [dialerProvider.overrideWithValue(dialer)],
      child: MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => result = Navigator.of(context).push<bool>(
              MaterialPageRoute(
                builder: (_) => ReportSentScreen(incident: _incident),
              ),
            ),
            child: const Text('abrir'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
  return (dialer: dialer, opened: () => result!);
}

void main() {
  testWidgets('confirma el envío y explica el anonimato', (tester) async {
    await _pump(tester);

    expect(find.text('Reporte enviado'), findsOneWidget);
    expect(find.textContaining('Sin verificar'), findsOneWidget);
    expect(find.textContaining('3 vecinos'), findsOneWidget);
    expect(
      find.textContaining(
        'Nadie, ni otros usuarios ni autoridades, puede ver quién envió este reporte',
      ),
      findsOneWidget,
    );
  });

  testWidgets('no promete alertas a otras personas (aún no existen)', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.textContaining('Avisamos'), findsNothing);
  });

  testWidgets('Llamar al 105 abre el marcador con ese número', (tester) async {
    final (:dialer, :opened) = await _pump(tester);

    await tester.tap(find.byKey(const Key('llamar-105')));
    await tester.pump();

    expect(dialer.dialed, ['105']);
    expect(
      find.text('Reporte enviado'),
      findsOneWidget,
      reason: 'sigue en la pantalla',
    );
  });

  testWidgets('Ver en el mapa cierra con true', (tester) async {
    final (:dialer, :opened) = await _pump(tester);

    await tester.tap(find.byKey(const Key('ver-en-el-mapa')));
    await tester.pumpAndSettle();

    expect(await opened(), isTrue);
  });
}
