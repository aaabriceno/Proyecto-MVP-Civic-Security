import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:civic_security/features/incident/data/incident_repository.dart';
import 'package:civic_security/features/incident/domain/incident.dart';
import 'package:civic_security/features/map/presentation/incident_detail.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import '../report/fakes.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

Incident _incident({bool tieneFoto = true}) => Incident(
  id: 'inc-1',
  tipo: IncidentType.robo,
  descripcion: 'Me robaron el celular',
  position: const LatLng(-16.4, -71.5),
  estado: IncidentStatus.sinVerificar,
  creadoEn: DateTime.now().toUtc(),
  tieneFoto: tieneFoto,
);

Future<ReportFakeRepo> _abrir(
  WidgetTester tester,
  Incident incident, {
  ReportFakeRepo? repo,
}) async {
  tester.view.physicalSize = const Size(1000, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final fake = repo ?? ReportFakeRepo();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [incidentRepositoryProvider.overrideWithValue(fake)],
      child: MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showIncidentDetail(context, incident),
            child: const Text('abrir'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  return fake;
}

void main() {
  testWidgets('un reporte sin foto no muestra nada de foto ni la pide', (
    tester,
  ) async {
    final repo = await _abrir(tester, _incident(tieneFoto: false));

    expect(find.byKey(const Key('detalle-incidente')), findsOneWidget);
    expect(find.byKey(const Key('foto-incidente')), findsNothing);
    expect(find.byKey(const Key('foto-cargando')), findsNothing);
    expect(repo.photoFetches, 0);
  });

  testWidgets('con foto: la pide al servidor y la muestra', (tester) async {
    final repo = ReportFakeRepo()..photos['inc-1'] = Uint8List.fromList(_png);
    await _abrir(tester, _incident(), repo: repo);
    await tester.pump();

    expect(repo.photoFetches, 1);
    final imagen = tester.widget<Image>(
      find.byKey(const Key('foto-incidente')),
    );
    expect((imagen.image as MemoryImage).bytes, _png);
    expect(
      imagen.fit,
      BoxFit.contain,
      reason: 'la foto se ve entera, no recortada',
    );
    expect(find.byKey(const Key('foto-cargando')), findsNothing);
  });

  testWidgets('el resto del detalle sigue ahí', (tester) async {
    final repo = ReportFakeRepo()..photos['inc-1'] = Uint8List.fromList(_png);
    await _abrir(tester, _incident(), repo: repo);

    expect(find.text('Robo'), findsOneWidget);
    expect(find.text('Me robaron el celular'), findsOneWidget);
  });

  testWidgets('mientras la descarga muestra un marcador', (tester) async {
    final repo = ReportFakeRepo()
      ..photos['inc-1'] = Uint8List.fromList(_png)
      ..fetchGate = Completer<void>();
    await _abrir(tester, _incident(), repo: repo);

    expect(find.byKey(const Key('foto-cargando')), findsOneWidget);
    expect(find.byKey(const Key('foto-incidente')), findsNothing);

    repo.fetchGate!.complete();
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('foto-cargando')), findsNothing);
    expect(find.byKey(const Key('foto-incidente')), findsOneWidget);
  });

  testWidgets('si no carga, lo dice y deja reintentar', (tester) async {
    final repo = ReportFakeRepo(); // sin foto guardada: falla con not_found
    await _abrir(tester, _incident(), repo: repo);
    await tester.pump();

    expect(find.byKey(const Key('foto-error')), findsOneWidget);
    expect(find.textContaining('No pudimos cargar la foto'), findsOneWidget);
    expect(find.byKey(const Key('foto-incidente')), findsNothing);

    repo.photos['inc-1'] = Uint8List.fromList(_png);
    await tester.tap(find.byKey(const Key('reintentar-foto-incidente')));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('foto-incidente')), findsOneWidget);
    expect(find.byKey(const Key('foto-error')), findsNothing);
    expect(repo.photoFetches, 2);
  });

  testWidgets('tocar la foto la abre en grande y se cierra', (tester) async {
    final repo = ReportFakeRepo()..photos['inc-1'] = Uint8List.fromList(_png);
    await _abrir(tester, _incident(), repo: repo);
    await tester.pump();

    await tester.tap(find.byKey(const Key('foto-incidente')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('foto-pantalla-completa')), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);

    await tester.tap(find.byKey(const Key('cerrar-foto')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('foto-pantalla-completa')), findsNothing);
  });

  testWidgets(
    'el detalle de un reporte alto cabe y se desplaza en una pantalla chica',
    (tester) async {
      final repo = ReportFakeRepo()..photos['inc-1'] = Uint8List.fromList(_png);
      tester.view.physicalSize = const Size(400, 500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [incidentRepositoryProvider.overrideWithValue(repo)],
          child: MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () => showIncidentDetail(context, _incident()),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      expect(tester.takeException(), isNull, reason: 'sin desbordamiento');
    },
  );
}
