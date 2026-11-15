import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:civic_security/core/media/photo_picker.dart';
import 'package:civic_security/core/media/photo_processor.dart';
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
import 'fake_photo_picker.dart';
import 'fakes.dart';

/// Lo que "toma" la cámara (nunca se dibuja, así que no hace falta que sea válido)
final _original = Uint8List.fromList([1, 2, 3]);

/// Lo que devuelve el preparador: un PNG de 1x1 válido, para que se pueda dibujar
final _preparada = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

class _NoDialer implements Dialer {
  @override
  Future<void> dial(String number) async {}
}

class _Ctx {
  _Ctx(this.picker, this.repo);
  final FakePhotoPicker picker;
  final ReportFakeRepo repo;
}

Future<_Ctx> _pump(
  WidgetTester tester, {
  FakePhotoPicker? picker,
  PhotoPreparer? preparer,
  ReportFakeRepo? repo,
}) async {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final fakePicker = picker ?? (FakePhotoPicker()..result = _original);
  final fakeRepo = repo ?? ReportFakeRepo();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        incidentRepositoryProvider.overrideWithValue(fakeRepo),
        tileProviderProvider.overrideWithValue(BlankTileProvider()),
        dialerProvider.overrideWithValue(_NoDialer()),
        photoPickerProvider.overrideWithValue(fakePicker),
        photoPreparerProvider.overrideWithValue(
          preparer ?? (_) async => _preparada,
        ),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push<Incident>(
              MaterialPageRoute(
                builder: (_) => const ReportScreen(
                  initialLocation: LatLng(-16.43, -71.505),
                  isUserLocation: true,
                  userPosition: LatLng(-16.43, -71.505),
                ),
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
  return _Ctx(fakePicker, fakeRepo);
}

Future<void> _tocar(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.tap(find.byKey(Key(key)));
  await tester.pump();
  await tester.pump();
}

Future<void> _enviar(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('tipo-robo')));
  await tester.pump();
  await _tocar(tester, 'enviar-reporte');
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  group('elegir la foto', () {
    testWidgets(
      'hay cámara y galería, y un aviso de privacidad sobre la foto',
      (tester) async {
        await _pump(tester);

        expect(find.text('Foto (opcional)'), findsOneWidget);
        expect(find.byKey(const Key('foto-camara')), findsOneWidget);
        expect(find.byKey(const Key('foto-galeria')), findsOneWidget);
        final aviso = find.byKey(const Key('aviso-foto'));
        expect(aviso, findsOneWidget);
        expect(
          find.descendant(of: aviso, matching: find.textContaining('rostros')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: aviso, matching: find.textContaining('placas')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('foto-previa')), findsNothing);
      },
    );

    testWidgets('Cámara: pide la foto a la cámara y muestra la vista previa', (
      tester,
    ) async {
      final ctx = await _pump(tester);

      await _tocar(tester, 'foto-camara');
      await tester.pumpAndSettle();

      expect(ctx.picker.requested, [PhotoSource.camera]);
      expect(find.byKey(const Key('foto-previa')), findsOneWidget);
      expect(find.byKey(const Key('foto-quitar')), findsOneWidget);
      expect(find.byKey(const Key('foto-camara')), findsNothing);
      expect(
        find.textContaining('sin ubicación ni datos del teléfono'),
        findsOneWidget,
      );
    });

    testWidgets('Galería: pide la foto a la galería', (tester) async {
      final ctx = await _pump(tester);

      await _tocar(tester, 'foto-galeria');
      await tester.pumpAndSettle();

      expect(ctx.picker.requested, [PhotoSource.gallery]);
      expect(find.byKey(const Key('foto-previa')), findsOneWidget);
    });

    testWidgets(
      'la vista previa muestra la foto ya preparada, no la original',
      (tester) async {
        await _pump(tester);

        await _tocar(tester, 'foto-camara');
        await tester.pumpAndSettle();

        final imagen = tester.widget<Image>(
          find.byKey(const Key('foto-previa')),
        );
        expect((imagen.image as MemoryImage).bytes, _preparada);
      },
    );

    testWidgets('si la persona cancela, no cambia nada y no hay error', (
      tester,
    ) async {
      final ctx = await _pump(tester, picker: FakePhotoPicker());

      await _tocar(tester, 'foto-camara');
      await tester.pumpAndSettle();

      expect(ctx.picker.requested, [PhotoSource.camera]);
      expect(find.byKey(const Key('foto-previa')), findsNothing);
      expect(find.byKey(const Key('foto-camara')), findsOneWidget);
      expect(find.byKey(const Key('error-foto')), findsNothing);
    });

    testWidgets('mientras prepara la foto lo dice y no deja elegir otra', (
      tester,
    ) async {
      final gate = Completer<Uint8List>();
      await _pump(tester, preparer: (_) => gate.future);

      await _tocar(tester, 'foto-camara');

      expect(find.byKey(const Key('foto-preparando')), findsOneWidget);
      expect(find.text('Preparando la foto…'), findsOneWidget);
      expect(find.byKey(const Key('foto-camara')), findsNothing);

      gate.complete(_preparada);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('foto-preparando')), findsNothing);
      expect(find.byKey(const Key('foto-previa')), findsOneWidget);
    });

    testWidgets('"Quitar" vuelve a ofrecer cámara y galería', (tester) async {
      await _pump(tester);
      await _tocar(tester, 'foto-camara');
      await tester.pumpAndSettle();

      await _tocar(tester, 'foto-quitar');

      expect(find.byKey(const Key('foto-previa')), findsNothing);
      expect(find.byKey(const Key('foto-camara')), findsOneWidget);
      expect(find.byKey(const Key('foto-galeria')), findsOneWidget);
    });
  });

  group('cuando no se puede', () {
    testWidgets('la cámara no abre', (tester) async {
      final picker = FakePhotoPicker()
        ..error = const PhotoPickerException(PhotoSource.camera);
      await _pump(tester, picker: picker);

      await _tocar(tester, 'foto-camara');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('error-foto')), findsOneWidget);
      expect(find.textContaining('No pudimos abrir la cámara'), findsOneWidget);
      expect(
        find.byKey(const Key('foto-camara')),
        findsOneWidget,
        reason: 'puede reintentar',
      );
    });

    testWidgets('la galería no abre', (tester) async {
      final picker = FakePhotoPicker()
        ..error = const PhotoPickerException(PhotoSource.gallery);
      await _pump(tester, picker: picker);

      await _tocar(tester, 'foto-galeria');
      await tester.pumpAndSettle();

      expect(
        find.textContaining('No pudimos abrir la galería'),
        findsOneWidget,
      );
    });

    testWidgets('la foto no se puede abrir (formato no compatible o dañada)', (
      tester,
    ) async {
      await _pump(
        tester,
        preparer: (_) async => throw const UnreadablePhotoException(),
      );

      await _tocar(tester, 'foto-galeria');
      await tester.pumpAndSettle();

      expect(find.textContaining('no se puede usar'), findsOneWidget);
      expect(find.byKey(const Key('foto-previa')), findsNothing);
    });

    testWidgets('la foto es demasiado grande', (tester) async {
      await _pump(
        tester,
        preparer: (_) async => throw const PhotoTooLargeException(),
      );

      await _tocar(tester, 'foto-galeria');
      await tester.pumpAndSettle();

      expect(find.textContaining('demasiado grande'), findsOneWidget);
    });

    testWidgets('un error inesperado al preparar tampoco rompe la pantalla', (
      tester,
    ) async {
      await _pump(tester, preparer: (_) async => throw StateError('algo raro'));

      await _tocar(tester, 'foto-camara');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('error-foto')), findsOneWidget);
      expect(find.byKey(const Key('enviar-reporte')), findsOneWidget);
    });

    testWidgets('el error se quita al elegir otra foto', (tester) async {
      final picker = FakePhotoPicker()
        ..error = const PhotoPickerException(PhotoSource.camera);
      await _pump(tester, picker: picker);
      await _tocar(tester, 'foto-camara');
      await tester.pumpAndSettle();

      picker
        ..error = null
        ..result = _original;
      await _tocar(tester, 'foto-camara');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('error-foto')), findsNothing);
      expect(find.byKey(const Key('foto-previa')), findsOneWidget);
    });
  });

  group('enviar con foto', () {
    testWidgets('sube la foto ya preparada, al reporte recién creado', (
      tester,
    ) async {
      final ctx = await _pump(tester);
      await _tocar(tester, 'foto-camara');
      await tester.pumpAndSettle();

      await _enviar(tester);
      await tester.pumpAndSettle();

      expect(ctx.repo.sent, hasLength(1));
      expect(ctx.repo.uploads, [('id-1', _preparada)]);
      expect(find.text('Reporte enviado'), findsOneWidget);
    });

    testWidgets('sin foto, enviar no sube nada', (tester) async {
      final ctx = await _pump(tester);

      await _enviar(tester);
      await tester.pumpAndSettle();

      expect(ctx.repo.sent, hasLength(1));
      expect(ctx.repo.uploads, isEmpty);
    });

    testWidgets('una foto quitada no se sube', (tester) async {
      final ctx = await _pump(tester);
      await _tocar(tester, 'foto-camara');
      await tester.pumpAndSettle();
      await _tocar(tester, 'foto-quitar');

      await _enviar(tester);
      await tester.pumpAndSettle();

      expect(ctx.repo.uploads, isEmpty);
    });

    testWidgets('con el reporte enviándose no se puede cambiar la foto', (
      tester,
    ) async {
      final repo = ReportFakeRepo()..gate = Completer<void>();
      await _pump(tester, repo: repo);
      await _tocar(tester, 'foto-camara');
      await tester.pumpAndSettle();

      await _enviar(tester);

      final quitar = tester.widget<TextButton>(
        find.byKey(const Key('foto-quitar')),
      );
      expect(quitar.onPressed, isNull);

      repo.gate!.complete();
      await tester.pumpAndSettle();
    });
  });

  group('la pantalla de "reporte enviado"', () {
    testWidgets('un reporte sin foto no habla de fotos', (tester) async {
      await _pump(tester);

      await _enviar(tester);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('estado-foto')), findsNothing);
    });

    testWidgets('con foto: "Subiendo la foto…" y luego "Foto adjunta"', (
      tester,
    ) async {
      final repo = ReportFakeRepo()..photoGate = Completer<void>();
      await _pump(tester, repo: repo);
      await _tocar(tester, 'foto-camara');
      await tester.pumpAndSettle();

      await _enviar(tester);
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Reporte enviado'), findsOneWidget);
      expect(find.text('Subiendo la foto…'), findsOneWidget);

      repo.photoGate!.complete();
      await tester.pumpAndSettle();

      expect(find.text('Subiendo la foto…'), findsNothing);
      expect(find.text('Foto adjunta'), findsOneWidget);
    });

    testWidgets('"Ver en el mapa" espera a que termine de subir la foto', (
      tester,
    ) async {
      final repo = ReportFakeRepo()..photoGate = Completer<void>();
      await _pump(tester, repo: repo);
      await _tocar(tester, 'foto-camara');
      await tester.pumpAndSettle();
      await _enviar(tester);
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('ver-en-el-mapa')))
            .onPressed,
        isNull,
      );

      repo.photoGate!.complete();
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('ver-en-el-mapa')))
            .onPressed,
        isNotNull,
      );
    });

    testWidgets(
      'si la foto falla: lo dice, el reporte sigue enviado y se puede reintentar',
      (tester) async {
        final repo = ReportFakeRepo()
          ..photoFailure = const ApiFailure.network();
        await _pump(tester, repo: repo);
        await _tocar(tester, 'foto-camara');
        await tester.pumpAndSettle();
        await _enviar(tester);
        await tester.pumpAndSettle();

        expect(find.text('Reporte enviado'), findsOneWidget);
        expect(find.textContaining('No pudimos subir la foto'), findsOneWidget);
        expect(find.byKey(const Key('reintentar-foto')), findsOneWidget);

        repo.photoFailure = null;
        await _tocar(tester, 'reintentar-foto');
        await tester.pumpAndSettle();

        expect(find.text('Foto adjunta'), findsOneWidget);
        expect(find.byKey(const Key('reintentar-foto')), findsNothing);
        expect(repo.sent, hasLength(1));
        expect(repo.uploads, hasLength(2));
      },
    );

    testWidgets('si la foto falla sin remedio, no ofrece reintentar', (
      tester,
    ) async {
      final repo = ReportFakeRepo()
        ..photoFailure = const ApiFailure(
          code: 'photo_has_metadata',
          message: 'x',
        );
      await _pump(tester, repo: repo);
      await _tocar(tester, 'foto-camara');
      await tester.pumpAndSettle();
      await _enviar(tester);
      await tester.pumpAndSettle();

      expect(find.textContaining('No pudimos usar la foto'), findsOneWidget);
      expect(find.byKey(const Key('reintentar-foto')), findsNothing);
      expect(find.byKey(const Key('ver-en-el-mapa')), findsOneWidget);
    });
  });
}
