import 'dart:async';
import 'dart:convert';

import 'package:civic_security/core/geo/arequipa.dart';
import 'package:civic_security/core/location/location_service.dart';
import 'package:civic_security/core/network/api_failure.dart';
import 'package:civic_security/features/incident/data/incident_repository.dart';
import 'package:civic_security/features/incident/domain/incident.dart';
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

/// Repositorio falso: devuelve [incidents], o lanza [failure] si se indica.
class _FakeRepo implements IncidentRepository {
  _FakeRepo({this.incidents = const [], this.failure});

  List<Incident> incidents;
  ApiFailure? failure;
  final calls = <Bbox>[];

  @override
  Future<List<Incident>> fetchSnapshot(Bbox bbox) async {
    calls.add(bbox);
    if (failure != null) throw failure!;
    return incidents;
  }
}

Incident _incident(
  String id, {
  IncidentType tipo = IncidentType.robo,
  IncidentStatus estado = IncidentStatus.sinVerificar,
  LatLng position = const LatLng(-16.4295, -71.5050), // ~55 m de _enArequipa
  String? descripcion,
}) => Incident(
  id: id,
  tipo: tipo,
  descripcion: descripcion,
  position: position,
  estado: estado,
  creadoEn: DateTime.now().toUtc().subtract(const Duration(minutes: 12)),
);

Future<MapController> _pumpMap(
  WidgetTester tester,
  _FakeLocationService service, {
  _FakeRepo? repo,
}) async {
  // Pantalla alta (la fuente de los tests es más ancha que la real)
  tester.view.physicalSize = const Size(1000, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final controller = MapController();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        locationServiceProvider.overrideWithValue(service),
        incidentRepositoryProvider.overrideWithValue(repo ?? _FakeRepo()),
        tileProviderProvider.overrideWithValue(_BlankTileProvider()),
      ],
      child: MaterialApp(home: MapScreen(mapController: controller)),
    ),
  );
  await tester.pump();
  await tester.pump();
  // El mapa espera 500 ms sin moverse antes de pedir los incidentes
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump();
  return controller;
}

void main() {
  testWidgets('muestra el mapa, sin pin central (ese es solo del reporte)', (
    tester,
  ) async {
    await _pumpMap(
      tester,
      _FakeLocationService(
        const LocationUnavailable(LocationFailure.unavailable),
      ),
    );

    expect(find.byType(FlutterMap), findsOneWidget);
    expect(find.byKey(const Key('pin-central')), findsNothing);
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

  group('incidentes en el mapa', () {
    final enZona = [
      _incident('a', tipo: IncidentType.robo),
      _incident(
        'b',
        tipo: IncidentType.peleaColegio,
        estado: IncidentStatus.verificado,
        position: const LatLng(-16.4298, -71.5052),
        descripcion: 'Pelea entre alumnos',
      ),
    ];

    _FakeLocationService conUsuario() =>
        _FakeLocationService(const LocationFound(_enArequipa));

    testWidgets('pide al servidor los incidentes del área visible', (
      tester,
    ) async {
      final repo = _FakeRepo(incidents: enZona);
      await _pumpMap(tester, conUsuario(), repo: repo);

      expect(repo.calls, isNotEmpty);
      final bbox = repo.calls.last;
      expect(bbox.minLat, lessThan(_enArequipa.latitude));
      expect(bbox.maxLat, greaterThan(_enArequipa.latitude));
      expect(bbox.minLng, lessThan(_enArequipa.longitude));
      expect(bbox.maxLng, greaterThan(_enArequipa.longitude));
      // Zoom 16: el área pedida es pequeña, no toda Arequipa
      expect(bbox.maxLat - bbox.minLat, lessThan(0.05));
    });

    testWidgets('dibuja un pin por incidente', (tester) async {
      await _pumpMap(tester, conUsuario(), repo: _FakeRepo(incidents: enZona));

      expect(find.byKey(const Key('pin-a')), findsOneWidget);
      expect(find.byKey(const Key('pin-b')), findsOneWidget);
    });

    testWidgets('la hoja inferior cuenta y lista los incidentes', (
      tester,
    ) async {
      await _pumpMap(tester, conUsuario(), repo: _FakeRepo(incidents: enZona));

      expect(find.text('2 incidentes en esta zona'), findsOneWidget);
      expect(find.text('Robo'), findsWidgets);
      expect(find.textContaining('Hace 12 min'), findsWidgets);
      expect(find.textContaining('m de ti'), findsWidgets);
      expect(find.text('Verificado'), findsWidgets);
    });

    testWidgets('sin incidentes lo dice claramente', (tester) async {
      await _pumpMap(tester, conUsuario(), repo: _FakeRepo());
      expect(find.text('Sin reportes en esta zona'), findsOneWidget);
    });

    testWidgets('un incidente se cuenta en singular', (tester) async {
      await _pumpMap(
        tester,
        conUsuario(),
        repo: _FakeRepo(incidents: [_incident('a')]),
      );
      expect(find.text('1 incidente en esta zona'), findsOneWidget);
    });

    testWidgets('filtrar por tipo oculta los demás pines y la lista', (
      tester,
    ) async {
      await _pumpMap(tester, conUsuario(), repo: _FakeRepo(incidents: enZona));

      await tester.tap(find.byKey(const Key('filtro-robo')));
      await tester.pump();

      expect(find.byKey(const Key('pin-a')), findsOneWidget);
      expect(find.byKey(const Key('pin-b')), findsNothing);
      expect(find.text('1 incidente en esta zona'), findsOneWidget);

      await tester.tap(find.byKey(const Key('filtro-todos')));
      await tester.pump();
      expect(find.byKey(const Key('pin-b')), findsOneWidget);
    });

    testWidgets(
      'un error de red avisa, conserva el mapa y permite reintentar',
      (tester) async {
        final repo = _FakeRepo(failure: const ApiFailure.network());
        await _pumpMap(tester, conUsuario(), repo: repo);

        expect(find.byKey(const Key('aviso-datos')), findsOneWidget);
        expect(
          find.text('No se pudo conectar con el servidor'),
          findsOneWidget,
        );
        expect(find.byType(FlutterMap), findsOneWidget);

        // El servidor vuelve: Reintentar carga los incidentes y quita el aviso
        repo
          ..failure = null
          ..incidents = enZona;
        await tester.tap(find.byKey(const Key('reintentar-datos')));
        await tester.pump();
        await tester.pump();

        expect(find.byKey(const Key('aviso-datos')), findsNothing);
        expect(find.byKey(const Key('pin-a')), findsOneWidget);
      },
    );

    testWidgets('tocar un pin muestra el detalle del incidente', (
      tester,
    ) async {
      await _pumpMap(tester, conUsuario(), repo: _FakeRepo(incidents: enZona));

      await tester.tap(find.byKey(const Key('pin-b')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('detalle-incidente')), findsOneWidget);
      expect(find.text('Pelea entre alumnos'), findsOneWidget);
      expect(find.text('Pelea en salida de colegio'), findsWidgets);
    });

    testWidgets('el detalle de un incidente sin descripción lo indica', (
      tester,
    ) async {
      await _pumpMap(
        tester,
        conUsuario(),
        repo: _FakeRepo(incidents: [_incident('a')]),
      );

      await tester.tap(find.byKey(const Key('pin-a')));
      await tester.pumpAndSettle();
      expect(find.text('Sin descripción'), findsOneWidget);
    });

    testWidgets('sin ubicación del usuario no inventa distancias', (
      tester,
    ) async {
      final service = _FakeLocationService(
        const LocationUnavailable(LocationFailure.denied),
      );
      await _pumpMap(tester, service, repo: _FakeRepo(incidents: enZona));

      expect(find.text('2 incidentes en esta zona'), findsOneWidget);
      expect(find.textContaining('m de ti'), findsNothing);
    });
  });

  test('arequipaBounds reconoce puntos dentro y fuera', () {
    expect(arequipaBounds.contains(_enArequipa), isTrue);
    expect(arequipaBounds.contains(const LatLng(-12.0464, -77.0428)), isFalse);
  });
}
