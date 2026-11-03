import 'package:civic_security/features/map/presentation/map_providers.dart';
import 'package:civic_security/features/report/presentation/adjust_location_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'blank_tiles.dart';

const _enArequipa = LatLng(-16.4300, -71.5050);
const _cercaDeElla = LatLng(-16.4290, -71.5050); // ~110 m al norte

/// Con qué se cerró la pantalla.
class _Outcome {
  bool closed = false;
  LatLng? value;
}

/// Abre la pantalla desde un botón para poder leer su resultado.
Future<_Outcome> _pump(
  WidgetTester tester, {
  LatLng initial = _enArequipa,
  LatLng? user,
}) async {
  tester.view.physicalSize = const Size(1000, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final outcome = _Outcome();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [tileProviderProvider.overrideWithValue(BlankTileProvider())],
      child: MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              outcome.value = await Navigator.of(context).push<LatLng>(
                MaterialPageRoute(
                  builder: (_) => AdjustLocationScreen(
                    initialCenter: initial,
                    userPosition: user,
                  ),
                ),
              );
              outcome.closed = true;
            },
            child: const Text('abrir'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
  return outcome;
}

void main() {
  testWidgets('pide ajustar el lugar y muestra el pin fijo al centro', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('¿Dónde ocurrió exactamente?'), findsOneWidget);
    expect(find.textContaining('Mueve el mapa'), findsOneWidget);
    expect(find.byKey(const Key('pin-central')), findsOneWidget);
    expect(find.byType(FlutterMap), findsOneWidget);
  });

  testWidgets('muestra la distancia al usuario cuando se conoce', (
    tester,
  ) async {
    await _pump(tester, initial: _cercaDeElla, user: _enArequipa);
    expect(find.textContaining('m de ti'), findsOneWidget);
    expect(find.byKey(const Key('mi-ubicacion')), findsOneWidget);
  });

  testWidgets('sin ubicación del usuario no inventa distancias', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.textContaining('de ti'), findsNothing);
    expect(find.byKey(const Key('usar-mi-ubicacion')), findsNothing);
  });

  testWidgets('en el mismo lugar del usuario lo dice con palabras', (
    tester,
  ) async {
    await _pump(tester, initial: _enArequipa, user: _enArequipa);
    expect(find.text('En tu ubicación'), findsOneWidget);
  });

  testWidgets('muestra las coordenadas elegidas', (tester) async {
    await _pump(tester);
    expect(find.textContaining('-16.43000'), findsOneWidget);
    expect(find.textContaining('-71.50500'), findsOneWidget);
  });

  testWidgets('fuera de Arequipa avisa y no deja confirmar', (tester) async {
    await _pump(tester, initial: const LatLng(-12.0464, -77.0428)); // Lima

    expect(find.textContaining('fuera de Arequipa'), findsOneWidget);
    final boton = tester.widget<FilledButton>(
      find.byKey(const Key('confirmar-ubicacion')),
    );
    expect(boton.onPressed, isNull);
  });

  testWidgets('Usar mi ubicación actual salta al usuario', (tester) async {
    await _pump(tester, initial: _cercaDeElla, user: _enArequipa);
    expect(find.text('En tu ubicación'), findsNothing);

    await tester.tap(find.byKey(const Key('usar-mi-ubicacion')));
    await tester.pump();
    expect(find.text('En tu ubicación'), findsOneWidget);
  });

  testWidgets('Confirmar devuelve el lugar donde está el pin', (tester) async {
    final outcome = await _pump(tester);

    await tester.tap(find.byKey(const Key('confirmar-ubicacion')));
    await tester.pumpAndSettle();

    expect(outcome.closed, isTrue);
    expect(outcome.value!.latitude, closeTo(_enArequipa.latitude, 1e-6));
    expect(outcome.value!.longitude, closeTo(_enArequipa.longitude, 1e-6));
  });

  testWidgets('tras Usar mi ubicación, Confirmar devuelve al usuario', (
    tester,
  ) async {
    final outcome = await _pump(
      tester,
      initial: _cercaDeElla,
      user: _enArequipa,
    );

    await tester.tap(find.byKey(const Key('usar-mi-ubicacion')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('confirmar-ubicacion')));
    await tester.pumpAndSettle();

    expect(outcome.value!.latitude, closeTo(_enArequipa.latitude, 1e-6));
  });

  testWidgets('Volver cierra sin devolver nada', (tester) async {
    final outcome = await _pump(tester);

    await tester.tap(find.byKey(const Key('volver')));
    await tester.pumpAndSettle();

    expect(outcome.closed, isTrue);
    expect(outcome.value, isNull);
  });
}
