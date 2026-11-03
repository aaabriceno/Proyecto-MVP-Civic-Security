import 'dart:async';
import 'dart:convert';

import 'package:civic_security/core/geo/arequipa.dart';
import 'package:civic_security/core/location/location_service.dart';
import 'package:civic_security/features/map/presentation/map_providers.dart';
import 'package:civic_security/features/map/presentation/map_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

/// Posición dentro de Arequipa (Paucarpata), lejos del centro de la vista inicial.
const _enArequipa = LatLng(-16.4300, -71.5050);

/// Vista de respaldo: toda Arequipa debe quedar visible, sin un punto fijo.
void _expectVistaDeArequipa(MapController controller) {
  expect(
    controller.camera.visibleBounds.containsBounds(arequipaBounds),
    isTrue,
    reason: 'sin ubicación se muestra Arequipa completa',
  );
  expect(controller.camera.zoom, lessThan(13));
}

/// Devuelve una imagen transparente: los tests no deben salir a internet.
class _BlankTileProvider extends TileProvider {
  // PNG transparente de 1x1 píxel
  static final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
  );

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      MemoryImage(_png);
}

class _FakeLocationService implements LocationService {
  _FakeLocationService(this.result, {Stream<LatLng>? updates})
    : updates = updates ?? const Stream.empty();

  final LocationState result;
  final Stream<LatLng> updates;
  int locateCalls = 0;
  int settingsCalls = 0;

  @override
  Future<LocationState> locate() async {
    locateCalls++;
    return result;
  }

  @override
  Stream<LatLng> watch() => updates;

  @override
  Future<void> openSettingsFor(LocationFailure reason) async => settingsCalls++;
}

Future<MapController> _pumpMap(
  WidgetTester tester,
  _FakeLocationService service,
) async {
  final controller = MapController();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        locationServiceProvider.overrideWithValue(service),
        tileProviderProvider.overrideWithValue(_BlankTileProvider()),
      ],
      child: MaterialApp(home: MapScreen(mapController: controller)),
    ),
  );
  await tester.pump();
  await tester.pump();
  return controller;
}

void main() {
  testWidgets('muestra el mapa y el pin central', (tester) async {
    await _pumpMap(
      tester,
      _FakeLocationService(
        const LocationUnavailable(LocationFailure.unavailable),
      ),
    );

    expect(find.byType(FlutterMap), findsOneWidget);
    expect(find.byKey(const Key('pin-central')), findsOneWidget);
  });

  testWidgets('con ubicación válida se centra en el usuario, sin aviso', (
    tester,
  ) async {
    final controller = await _pumpMap(
      tester,
      _FakeLocationService(const LocationFound(_enArequipa)),
    );

    expect(
      controller.camera.center.latitude,
      closeTo(_enArequipa.latitude, 1e-6),
    );
    expect(
      controller.camera.center.longitude,
      closeTo(_enArequipa.longitude, 1e-6),
    );
    expect(find.byKey(const Key('mi-ubicacion')), findsOneWidget);
    expect(find.byKey(const Key('aviso-ubicacion')), findsNothing);
  });

  testWidgets('sin permiso muestra Arequipa y un aviso con Reintentar', (
    tester,
  ) async {
    final service = _FakeLocationService(
      const LocationUnavailable(LocationFailure.denied),
    );
    final controller = await _pumpMap(tester, service);

    _expectVistaDeArequipa(controller);
    expect(find.byKey(const Key('aviso-ubicacion')), findsOneWidget);
    expect(find.textContaining('ubicación'), findsWidgets);
    expect(find.textContaining('UCSP'), findsNothing);
    expect(find.byKey(const Key('mi-ubicacion')), findsNothing);

    await tester.tap(find.text('Reintentar'));
    await tester.pump();
    await tester.pump();
    expect(service.locateCalls, 2);
  });

  testWidgets('GPS apagado o permiso bloqueado ofrece abrir los ajustes', (
    tester,
  ) async {
    final service = _FakeLocationService(
      const LocationUnavailable(LocationFailure.deniedForever),
    );
    await _pumpMap(tester, service);

    await tester.tap(find.text('Ajustes'));
    await tester.pump();
    expect(service.settingsCalls, 1);
  });

  testWidgets('fuera de Arequipa muestra Arequipa y lo explica', (
    tester,
  ) async {
    final controller = await _pumpMap(
      tester,
      // California, la ubicación por defecto del emulador de Android
      _FakeLocationService(const LocationFound(LatLng(37.4220, -122.0841))),
    );

    _expectVistaDeArequipa(controller);
    expect(find.textContaining('fuera de Arequipa'), findsOneWidget);
    expect(find.textContaining('UCSP'), findsNothing);
    expect(find.byKey(const Key('mi-ubicacion')), findsNothing);
  });

  testWidgets('seguir al usuario mueve el punto pero no la cámara', (
    tester,
  ) async {
    final updates = StreamController<LatLng>();
    addTearDown(updates.close);
    final controller = await _pumpMap(
      tester,
      _FakeLocationService(
        const LocationFound(_enArequipa),
        updates: updates.stream,
      ),
    );
    final antes = tester.getCenter(find.byKey(const Key('mi-ubicacion')));

    // ~55 m al norte: sigue dentro de la pantalla
    updates.add(const LatLng(-16.4295, -71.5050));
    await tester.pump();
    await tester.pump();

    final despues = tester.getCenter(find.byKey(const Key('mi-ubicacion')));
    expect(
      despues.dy,
      lessThan(antes.dy),
      reason: 'el punto subió en pantalla',
    );
    // El usuario puede estar explorando el mapa: no se le "roba" la cámara
    expect(
      controller.camera.center.latitude,
      closeTo(_enArequipa.latitude, 1e-6),
    );
  });

  testWidgets('el botón Mi ubicación recentra el mapa en el usuario', (
    tester,
  ) async {
    final controller = await _pumpMap(
      tester,
      _FakeLocationService(const LocationFound(_enArequipa)),
    );

    const otroLugar = LatLng(-16.3900, -71.5600);
    controller.move(otroLugar, 16);
    await tester.pump();
    expect(controller.camera.center, otroLugar);

    await tester.tap(find.byKey(const Key('boton-mi-ubicacion')));
    await tester.pump();
    expect(
      controller.camera.center.latitude,
      closeTo(_enArequipa.latitude, 1e-6),
    );
  });

  test('arequipaBounds reconoce puntos dentro y fuera', () {
    expect(arequipaBounds.contains(_enArequipa), isTrue);
    expect(arequipaBounds.contains(const LatLng(-12.0464, -77.0428)), isFalse);
  });
}
