import 'dart:async';
import 'dart:convert';

import 'package:civic_security/core/geo/arequipa.dart';
import 'package:civic_security/core/location/location_service.dart';
import 'package:civic_security/core/network/api_failure.dart';
import 'package:civic_security/features/auth/domain/auth_models.dart';
import 'package:civic_security/features/auth/presentation/auth_controller.dart';
import 'package:civic_security/features/incident/data/incident_repository.dart';
import 'package:civic_security/features/incident/domain/incident.dart';
import 'package:civic_security/features/report/domain/new_incident.dart';
import 'package:civic_security/core/realtime/phoenix_channel.dart';
import 'package:civic_security/features/map/data/incident_stream.dart';
import 'package:civic_security/features/map/presentation/map_providers.dart';
import 'package:civic_security/features/map/presentation/map_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'fake_incident_stream.dart';

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
  _FakeLocationService(this.result, {Stream<LocationFound>? updates})
    : updates = updates ?? const Stream.empty();

  final LocationState result;
  final Stream<LocationFound> updates;
  int locateCalls = 0;
  int settingsCalls = 0;

  @override
  Future<LocationState> locate() async {
    locateCalls++;
    return result;
  }

  @override
  Stream<LocationFound> watch() => updates;

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
  Future<Incident> create(
    NewIncident input, {
    required String idempotencyKey,
  }) => throw UnimplementedError();

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

/// Sesión de mentira: el estado que el test indique y un contador de cierres.
class _FakeAuth extends AuthController {
  _FakeAuth(this._initial);

  final AuthState _initial;
  int logouts = 0;

  @override
  AuthState build() => _initial;

  @override
  Future<void> logout() async {
    logouts++;
    state = const AuthState.signedOut();
  }
}

Future<MapController> _pumpMap(
  WidgetTester tester,
  _FakeLocationService service, {
  _FakeRepo? repo,
  FakeIncidentStream? stream,
  _FakeAuth? auth,
  bool readOnly = false,
  VoidCallback? onSignIn,
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
        // Nunca abrir un WebSocket real en los tests
        incidentStreamProvider.overrideWithValue(
          stream ?? FakeIncidentStream(),
        ),
        tileProviderProvider.overrideWithValue(_BlankTileProvider()),
        if (auth != null) authControllerProvider.overrideWith(() => auth),
      ],
      child: MaterialApp(
        home: MapScreen(
          mapController: controller,
          readOnly: readOnly,
          onSignIn: onSignIn,
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  // El mapa espera 500 ms sin moverse antes de pedir los incidentes
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump();
  return controller;
}

/// Entrega un evento del stream falso y deja que la pantalla se reconstruya.
Future<void> _deliver(WidgetTester tester) async {
  await tester.pump(); // el stream entrega el evento (microtask)
  await tester.pump(); // la pantalla se reconstruye con el nuevo estado
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

  group('círculo de precisión', () {
    List<CircleMarker> circulos(WidgetTester tester) =>
        tester.widget<CircleLayer>(find.byType(CircleLayer)).circles;

    testWidgets('dibuja un círculo con la precisión, en metros reales', (
      tester,
    ) async {
      await _pumpMap(
        tester,
        _FakeLocationService(
          const LocationFound(_enArequipa, accuracyMeters: 350),
        ),
      );

      final circulo = circulos(tester).single;
      expect(circulo.point, _enArequipa);
      expect(circulo.radius, 350);
      // Metros del terreno, no píxeles: crece o se achica con el zoom
      expect(circulo.useRadiusInMeter, isTrue);
    });

    testWidgets('sin precisión conocida no inventa un círculo', (tester) async {
      await _pumpMap(
        tester,
        _FakeLocationService(const LocationFound(_enArequipa)),
      );

      expect(find.byType(CircleLayer), findsNothing);
      // El punto del usuario sí sigue estando
      expect(find.byKey(const Key('mi-ubicacion')), findsOneWidget);
    });

    testWidgets(
      'el círculo sigue al usuario y se ajusta a la nueva precisión',
      (tester) async {
        final updates = StreamController<LocationFound>();
        addTearDown(updates.close);
        await _pumpMap(
          tester,
          _FakeLocationService(
            const LocationFound(_enArequipa, accuracyMeters: 350),
            updates: updates.stream,
          ),
        );

        // El GPS por fin engancha: se mueve un poco y la precisión mejora
        const nueva = LatLng(-16.4295, -71.5050);
        updates.add(const LocationFound(nueva, accuracyMeters: 12));
        await tester.pump();
        await tester.pump();

        final circulo = circulos(tester).single;
        expect(circulo.radius, 12);
        expect(circulo.point, nueva);
      },
    );
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
    final updates = StreamController<LocationFound>();
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
    updates.add(const LocationFound(LatLng(-16.4295, -71.5050)));
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

  group('reportar', () {
    testWidgets('con ubicación abre el formulario con "Tu ubicación actual"', (
      tester,
    ) async {
      await _pumpMap(
        tester,
        _FakeLocationService(const LocationFound(_enArequipa)),
      );

      await tester.tap(find.byKey(const Key('boton-reportar')));
      await tester.pumpAndSettle();

      expect(find.text('¿Qué está pasando?'), findsOneWidget);
      expect(find.text('Tu ubicación actual'), findsOneWidget);
    });

    testWidgets('sin ubicación pide primero elegir el lugar en el mapa', (
      tester,
    ) async {
      await _pumpMap(
        tester,
        _FakeLocationService(const LocationUnavailable(LocationFailure.denied)),
      );

      await tester.tap(find.byKey(const Key('boton-reportar')));
      await tester.pumpAndSettle();
      expect(find.text('¿Dónde ocurrió exactamente?'), findsOneWidget);

      await tester.tap(find.byKey(const Key('confirmar-ubicacion')));
      await tester.pumpAndSettle();
      expect(find.text('¿Qué está pasando?'), findsOneWidget);
      expect(find.text('Ubicación elegida en el mapa'), findsOneWidget);
    });

    testWidgets('cancelar el ajuste de ubicación vuelve al mapa', (
      tester,
    ) async {
      await _pumpMap(
        tester,
        _FakeLocationService(const LocationUnavailable(LocationFailure.denied)),
      );

      await tester.tap(find.byKey(const Key('boton-reportar')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('volver')));
      await tester.pumpAndSettle();

      expect(find.text('¿Qué está pasando?'), findsNothing);
      expect(find.byKey(const Key('boton-reportar')), findsOneWidget);
    });
  });

  group('tiempo real', () {
    final denied = _FakeLocationService(
      const LocationUnavailable(LocationFailure.denied),
    );

    testWidgets('al abrir la pantalla empieza a escuchar', (tester) async {
      final stream = FakeIncidentStream();
      await _pumpMap(tester, denied, stream: stream);

      expect(stream.starts, 1);
    });

    testWidgets('el indicador sigue el estado de la conexión', (tester) async {
      final stream = FakeIncidentStream();
      await _pumpMap(tester, denied, stream: stream);

      stream.setStatus(RealtimeStatus.connecting);
      await _deliver(tester);
      expect(find.text('Conectando…'), findsOneWidget);

      stream.setStatus(RealtimeStatus.connected);
      await _deliver(tester);
      expect(find.text('En vivo'), findsOneWidget);

      stream.setStatus(RealtimeStatus.disconnected);
      await _deliver(tester);
      expect(find.text('Reconectando…'), findsOneWidget);
    });

    testWidgets('un reporte nuevo aparece como pin sin recargar', (
      tester,
    ) async {
      final stream = FakeIncidentStream();
      final repo = _FakeRepo();
      await _pumpMap(tester, denied, repo: repo, stream: stream);
      expect(find.byKey(const Key('pin-nuevo')), findsNothing);
      final loadsBefore = repo.calls.length;

      stream.emit(_incident('nuevo'));
      await _deliver(tester);

      expect(find.byKey(const Key('pin-nuevo')), findsOneWidget);
      expect(repo.calls, hasLength(loadsBefore), reason: 'sin pedir nada');
    });

    testWidgets('al quedar conectado recarga lo que pudo perderse', (
      tester,
    ) async {
      final stream = FakeIncidentStream();
      final repo = _FakeRepo();
      await _pumpMap(tester, denied, repo: repo, stream: stream);
      final loadsBefore = repo.calls.length;
      repo.incidents = [_incident('llego-mientras-no-escuchaba')];

      stream.setStatus(RealtimeStatus.connected);
      await _deliver(tester);
      await tester.pump(); // llega la respuesta del snapshot

      expect(repo.calls, hasLength(loadsBefore + 1));
      expect(
        find.byKey(const Key('pin-llego-mientras-no-escuchaba')),
        findsOneWidget,
      );
    });

    testWidgets('en segundo plano corta la conexión y al volver reconecta', (
      tester,
    ) async {
      final stream = FakeIncidentStream();
      await _pumpMap(tester, denied, stream: stream);
      final binding = tester.binding;

      // Un diálogo del sistema (permisos) pone la app en "inactive": no corta
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      expect(stream.stops, 0);

      binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      expect(stream.stops, 1);

      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(stream.starts, 2);
    });
  });

  group('cuenta', () {
    const unaCuenta = AuthUser(
      id: '89e95dd3-b844-4c68-8186-c778448e407a',
      alias: 'Halcon-Misti-482',
      nivel: AuthLevel.invitado,
    );
    final enArequipa = _FakeLocationService(const LocationFound(_enArequipa));

    testWidgets('con sesión, el botón de cuenta abre la hoja con el alias', (
      tester,
    ) async {
      await _pumpMap(
        tester,
        enArequipa,
        auth: _FakeAuth(const AuthState.signedIn(unaCuenta)),
      );

      await tester.tap(find.byKey(const Key('boton-cuenta')));
      await tester.pumpAndSettle();

      expect(find.text('Halcon-Misti-482'), findsOneWidget);
      expect(find.text('Cuenta sin verificar'), findsOneWidget);
    });

    testWidgets('"Cerrar sesión" cierra la sesión y la hoja', (tester) async {
      final auth = _FakeAuth(const AuthState.signedIn(unaCuenta));
      await _pumpMap(tester, enArequipa, auth: auth);

      await tester.tap(find.byKey(const Key('boton-cuenta')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('boton-cerrar-sesion')));
      await tester.pumpAndSettle();

      expect(auth.logouts, 1);
      expect(find.byKey(const Key('boton-cerrar-sesion')), findsNothing);
    });

    testWidgets(
      'sin confirmar la sesión (sin señal) lo avisa y deja usar el mapa',
      (tester) async {
        await _pumpMap(
          tester,
          enArequipa,
          auth: _FakeAuth(const AuthState.offline()),
        );

        expect(
          find.byKey(const Key('aviso-sesion-sin-confirmar')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('boton-reportar')), findsOneWidget);
        expect(find.byKey(const Key('boton-cuenta')), findsOneWidget);
      },
    );

    testWidgets('con la sesión confirmada no hay aviso', (tester) async {
      await _pumpMap(
        tester,
        enArequipa,
        auth: _FakeAuth(const AuthState.signedIn(unaCuenta)),
      );

      expect(find.byKey(const Key('aviso-sesion-sin-confirmar')), findsNothing);
    });

    testWidgets(
      'solo lectura: no se puede reportar y se ofrece iniciar sesión',
      (tester) async {
        var pidioSesion = false;
        await _pumpMap(
          tester,
          enArequipa,
          readOnly: true,
          onSignIn: () => pidioSesion = true,
        );

        expect(find.byKey(const Key('boton-reportar')), findsNothing);
        expect(find.byKey(const Key('boton-cuenta')), findsNothing);

        await tester.tap(find.byKey(const Key('boton-iniciar-sesion-mapa')));

        expect(pidioSesion, isTrue);
      },
    );

    testWidgets('solo lectura sigue mostrando los reportes y la ubicación', (
      tester,
    ) async {
      await _pumpMap(
        tester,
        enArequipa,
        repo: _FakeRepo(incidents: [_incident('a')]),
        readOnly: true,
        onSignIn: () {},
      );

      expect(find.byKey(const Key('pin-a')), findsOneWidget);
      expect(find.byKey(const Key('mi-ubicacion')), findsOneWidget);
      expect(find.byKey(const Key('boton-mi-ubicacion')), findsOneWidget);
    });
  });

  test('arequipaBounds reconoce puntos dentro y fuera', () {
    expect(arequipaBounds.contains(_enArequipa), isTrue);
    expect(arequipaBounds.contains(const LatLng(-12.0464, -77.0428)), isFalse);
  });
}
