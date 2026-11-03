import 'dart:async';

import 'package:civic_security/core/network/api_failure.dart';
import 'package:civic_security/core/phone/dialer.dart';
import 'package:civic_security/features/incident/data/incident_repository.dart';
import 'package:civic_security/features/incident/domain/incident.dart';
import 'package:civic_security/features/map/presentation/map_providers.dart';
import 'package:civic_security/features/report/presentation/report_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'blank_tiles.dart';
import 'fakes.dart';

const _aqui = LatLng(-16.4300, -71.5050);
const _otroLugar = LatLng(-16.4290, -71.5050);

class _NoDialer implements Dialer {
  @override
  Future<void> dial(String number) async {}
}

/// Con qué se cerró el formulario.
class _Outcome {
  bool closed = false;
  Incident? incident;
}

Future<(_Outcome, ReportFakeRepo)> _pump(
  WidgetTester tester, {
  ReportFakeRepo? repo,
  LatLng location = _aqui,
  bool isUserLocation = true,
  LatLng? user = _aqui,
}) async {
  tester.view.physicalSize = const Size(1000, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final fake = repo ?? ReportFakeRepo();
  final outcome = _Outcome();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        incidentRepositoryProvider.overrideWithValue(fake),
        tileProviderProvider.overrideWithValue(BlankTileProvider()),
        dialerProvider.overrideWithValue(_NoDialer()),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              outcome.incident = await Navigator.of(context).push<Incident>(
                MaterialPageRoute(
                  builder: (_) => ReportScreen(
                    initialLocation: location,
                    isUserLocation: isUserLocation,
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
  return (outcome, fake);
}

Future<void> _enviar(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('enviar-reporte')));
  await tester.tap(find.byKey(const Key('enviar-reporte')));
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('muestra el formulario del diseño con los 6 tipos', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('¿Qué está pasando?'), findsOneWidget);
    expect(find.text('Anónimo'), findsOneWidget);
    for (final label in [
      'Robo / asalto',
      'Agresión a mujer',
      'Maltrato animal',
      'Pelea / riña',
      'Actividad sospechosa',
      'Otro',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('Enviar reporte anónimo'), findsOneWidget);
  });

  testWidgets('avisa que no se escriban datos personales', (tester) async {
    await _pump(tester);
    expect(
      find.textContaining('No escribas nombres, DNI, teléfonos ni correos'),
      findsOneWidget,
    );
  });

  testWidgets('avisa que el pin del mapa es público', (tester) async {
    await _pump(tester);
    expect(find.textContaining('ubicación del pin es pública'), findsOneWidget);
  });

  testWidgets('no envía sin elegir un tipo', (tester) async {
    final (_, repo) = await _pump(tester);

    await _enviar(tester);

    expect(find.text('Elige un tipo de incidente'), findsOneWidget);
    expect(repo.sent, isEmpty);
  });

  testWidgets('elegir un tipo quita el aviso', (tester) async {
    await _pump(tester);
    await _enviar(tester);
    expect(find.text('Elige un tipo de incidente'), findsOneWidget);

    await tester.tap(find.byKey(const Key('tipo-robo')));
    await tester.pump();
    expect(find.text('Elige un tipo de incidente'), findsNothing);
  });

  testWidgets('envía tipo, descripción recortada y ubicación', (tester) async {
    final (_, repo) = await _pump(tester);

    await tester.tap(find.byKey(const Key('tipo-agresion_mujer')));
    await tester.enterText(
      find.byKey(const Key('descripcion')),
      '  Acosan a las chicas  ',
    );
    await _enviar(tester);

    final (input, key) = repo.sent.single;
    expect(input.tipo, IncidentType.agresionMujer);
    expect(input.descripcion?.trim(), 'Acosan a las chicas');
    expect((input.lat, input.lng), (_aqui.latitude, _aqui.longitude));
    expect(key, isNotEmpty);
  });

  testWidgets('la descripción es opcional', (tester) async {
    final (_, repo) = await _pump(tester);

    await tester.tap(find.byKey(const Key('tipo-otro')));
    await _enviar(tester);

    expect(repo.sent.single.$1.toJson().containsKey('descripcion'), isFalse);
  });

  testWidgets('al enviar bien muestra "Reporte enviado"', (tester) async {
    await _pump(tester);
    await tester.tap(find.byKey(const Key('tipo-robo')));
    await _enviar(tester);
    await tester.pumpAndSettle();

    expect(find.text('Reporte enviado'), findsOneWidget);
  });

  testWidgets('Ver en el mapa devuelve el incidente creado', (tester) async {
    final (outcome, _) = await _pump(tester);
    await tester.tap(find.byKey(const Key('tipo-robo')));
    await _enviar(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('ver-en-el-mapa')));
    await tester.pumpAndSettle();

    expect(outcome.closed, isTrue);
    expect(outcome.incident?.tipo, IncidentType.robo);
  });

  testWidgets('cerrar la confirmación sin ver el mapa no devuelve nada', (
    tester,
  ) async {
    final (outcome, _) = await _pump(tester);
    await tester.tap(find.byKey(const Key('tipo-robo')));
    await _enviar(tester);
    await tester.pumpAndSettle();

    final context = tester.element(find.text('Reporte enviado'));
    Navigator.of(context).pop();
    await tester.pumpAndSettle();

    expect(outcome.closed, isTrue);
    expect(outcome.incident, isNull);
  });

  testWidgets('Cancelar cierra el formulario sin enviar', (tester) async {
    final (outcome, repo) = await _pump(tester);

    await tester.tap(find.byKey(const Key('cancelar-reporte')));
    await tester.pumpAndSettle();

    expect(outcome.closed, isTrue);
    expect(outcome.incident, isNull);
    expect(repo.sent, isEmpty);
  });

  testWidgets('un doble toque en Enviar envía una sola vez', (tester) async {
    final repo = ReportFakeRepo()..gate = Completer<void>();
    await _pump(tester, repo: repo);
    await tester.tap(find.byKey(const Key('tipo-robo')));

    await _enviar(tester);
    await _enviar(tester);

    expect(repo.sent.length, 1);
    final boton = tester.widget<FilledButton>(
      find.byKey(const Key('enviar-reporte')),
    );
    expect(boton.onPressed, isNull, reason: 'deshabilitado mientras envía');

    repo.gate!.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('el error de la descripción se ve junto al campo', (
    tester,
  ) async {
    final repo = ReportFakeRepo()
      ..failure = const ApiFailure(
        code: 'validation_failed',
        message: 'Datos inválidos',
        fields: {
          'descripcion': [
            'no escribas datos personales (DNI, teléfonos, correos ni enlaces)',
          ],
        },
      );
    await _pump(tester, repo: repo);
    await tester.tap(find.byKey(const Key('tipo-robo')));
    await tester.enterText(
      find.byKey(const Key('descripcion')),
      'llámame al 987654321',
    );
    await _enviar(tester);

    expect(
      find.textContaining('no escribas datos personales (DNI'),
      findsOneWidget,
    );
    expect(find.text('Reporte enviado'), findsNothing);
  });

  testWidgets('el error de ubicación se ve junto a la ubicación', (
    tester,
  ) async {
    final repo = ReportFakeRepo()
      ..failure = const ApiFailure(
        code: 'validation_failed',
        message: 'Datos inválidos',
        fields: {
          'ubicacion': ['La ubicación debe estar dentro de Arequipa'],
        },
      );
    await _pump(tester, repo: repo);
    await tester.tap(find.byKey(const Key('tipo-robo')));
    await _enviar(tester);

    expect(
      find.text('La ubicación debe estar dentro de Arequipa'),
      findsOneWidget,
    );
  });

  testWidgets('un error de red avisa y deja reintentar con la misma clave', (
    tester,
  ) async {
    final repo = ReportFakeRepo()..failure = const ApiFailure.network();
    await _pump(tester, repo: repo);
    await tester.tap(find.byKey(const Key('tipo-robo')));
    await _enviar(tester);

    expect(find.text('No se pudo conectar con el servidor'), findsOneWidget);
    final boton = tester.widget<FilledButton>(
      find.byKey(const Key('enviar-reporte')),
    );
    expect(boton.onPressed, isNotNull, reason: 'se puede reintentar');

    repo.failure = null;
    await _enviar(tester);
    await tester.pumpAndSettle();

    expect(repo.sent.length, 2);
    expect(
      repo.sent[0].$2,
      repo.sent[1].$2,
      reason: 'mismo reporte: no se duplica',
    );
    expect(find.text('Reporte enviado'), findsOneWidget);
  });

  group('ubicación', () {
    testWidgets('la ubicación actual se indica como tal', (tester) async {
      await _pump(tester);
      expect(find.text('Tu ubicación actual'), findsOneWidget);
    });

    testWidgets('una ubicación elegida en el mapa se indica como tal', (
      tester,
    ) async {
      await _pump(tester, isUserLocation: false, user: null);
      expect(find.text('Ubicación elegida en el mapa'), findsOneWidget);
    });

    testWidgets('Cambiar abre el ajuste de ubicación', (tester) async {
      await _pump(tester);
      await tester.tap(find.byKey(const Key('cambiar-ubicacion')));
      await tester.pumpAndSettle();
      expect(find.text('¿Dónde ocurrió exactamente?'), findsOneWidget);
    });

    testWidgets('una ubicación ajustada se usa al enviar', (tester) async {
      // El pin está en otro lugar; el usuario vuelve a su ubicación y confirma
      final (_, repo) = await _pump(
        tester,
        location: _otroLugar,
        isUserLocation: false,
      );
      expect(find.text('Ubicación elegida en el mapa'), findsOneWidget);

      await tester.tap(find.byKey(const Key('cambiar-ubicacion')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('usar-mi-ubicacion')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('confirmar-ubicacion')));
      await tester.pumpAndSettle();

      expect(find.text('Tu ubicación actual'), findsOneWidget);

      await tester.tap(find.byKey(const Key('tipo-robo')));
      await _enviar(tester);
      expect(repo.sent.single.$1.lat, closeTo(_aqui.latitude, 1e-6));
    });
  });
}
