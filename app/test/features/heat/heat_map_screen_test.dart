import 'package:civic_security/core/network/api_failure.dart';
import 'package:civic_security/features/heat/data/heat_repository.dart';
import 'package:civic_security/features/heat/domain/heat_map.dart';
import 'package:civic_security/features/heat/presentation/heat_map_screen.dart';
import 'package:civic_security/features/incident/domain/incident.dart';
import 'package:civic_security/features/map/presentation/map_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import '../report/blank_tiles.dart';

const _centro = LatLng(-16.4090, -71.5370);

HeatCell _celda({int count = 7}) => HeatCell(
  position: _centro,
  count: count,
  tipos: const {IncidentType.robo: 5, IncidentType.peleaColegio: 2},
  franjaDesde: 18,
  franjaHasta: 21,
);

/// Repositorio falso: devuelve lo que el test deje en [respuesta].
class _FakeRepo implements HeatRepository {
  _FakeRepo(this.respuesta);

  Object respuesta; // HeatMap o ApiFailure
  final calls = <(Bbox, HeatWindow)>[];

  @override
  Future<HeatMap> fetch(Bbox bbox, HeatWindow window) async {
    calls.add((bbox, window));
    final r = respuesta;
    if (r is ApiFailure) throw r;
    return r as HeatMap;
  }
}

HeatMap _conUnaCelda({int count = 7}) => HeatMap(
  cellDeg: 0.005,
  max: count,
  cells: [_celda(count: count)],
);

/// Abre la pantalla desde un botón para poder leer con qué se cerró.
class _Outcome {
  bool closed = false;
  LatLng? value;
}

Future<_Outcome> _pump(WidgetTester tester, _FakeRepo repo) async {
  tester.view.physicalSize = const Size(1000, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final outcome = _Outcome();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        tileProviderProvider.overrideWithValue(BlankTileProvider()),
        heatRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              outcome.value = await Navigator.of(context).push<LatLng>(
                MaterialPageRoute(
                  builder: (_) => const HeatMapScreen(
                    initialCenter: _centro,
                    initialZoom: 15,
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

Finder _circles() => find.byType(CircleLayer);

/// Toca el mapa. flutter_map espera ~250 ms para distinguir un toque de un doble
/// toque, con un Timer: `pumpAndSettle` no adelanta el reloj si no hay cuadros
/// pendientes, así que se avanza a mano.
Future<void> _tapAt(WidgetTester tester, Offset position) async {
  await tester.tapAt(position);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('al abrir pide la zona visible en 24 h y la marca elegida', (
    tester,
  ) async {
    final repo = _FakeRepo(_conUnaCelda());
    await _pump(tester, repo);

    expect(repo.calls, hasLength(1));
    expect(repo.calls.single.$2, HeatWindow.day);
    final bbox = repo.calls.single.$1;
    expect(bbox.contains(_centro), isTrue, reason: 'la zona incluye el centro');

    for (final w in HeatWindow.values) {
      expect(find.text(w.label), findsOneWidget);
    }
  });

  testWidgets('tocar "7 días" vuelve a pedir con esa ventana', (tester) async {
    final repo = _FakeRepo(_conUnaCelda());
    await _pump(tester, repo);

    await tester.tap(find.byKey(const Key('chip-ventana-7d')));
    await tester.pumpAndSettle();

    expect(repo.calls.last.$2, HeatWindow.week);
  });

  testWidgets('tocar "Última hora" pide 1h', (tester) async {
    final repo = _FakeRepo(_conUnaCelda());
    await _pump(tester, repo);

    await tester.tap(find.byKey(const Key('chip-ventana-1h')));
    await tester.pumpAndSettle();

    expect(repo.calls.last.$2, HeatWindow.hour);
  });

  testWidgets('dibuja círculos concéntricos por cada celda', (tester) async {
    await _pump(tester, _FakeRepo(_conUnaCelda()));

    final layer = tester.widget<CircleLayer>(_circles());
    expect(layer.circles, hasLength(3));
    expect(layer.circles.every((c) => c.useRadiusInMeter), isTrue);
    expect(layer.circles.first.point, _centro);
    // De afuera hacia adentro: cada círculo es más chico que el anterior
    final radios = [for (final c in layer.circles) c.radius];
    expect(radios, [...radios]..sort((a, b) => b.compareTo(a)));
  });

  testWidgets('una celda más caliente se pinta distinto a una más fría', (
    tester,
  ) async {
    final caliente = _FakeRepo(_conUnaCelda(count: 8));
    await _pump(tester, caliente);
    final colorCaliente = tester
        .widget<CircleLayer>(_circles())
        .circles
        .last
        .color;

    final fria = _FakeRepo(_conUnaCelda(count: 1));
    await tester.pumpWidget(const SizedBox());
    await _pump(tester, fria);
    final colorFrio = tester.widget<CircleLayer>(_circles()).circles.last.color;

    expect(colorCaliente, isNot(colorFrio));
  });

  testWidgets('muestra la leyenda de intensidad', (tester) async {
    await _pump(tester, _FakeRepo(_conUnaCelda()));

    expect(find.byKey(const Key('leyenda-intensidad')), findsOneWidget);
    expect(find.text('Intensidad'), findsOneWidget);
    expect(find.text('Baja'), findsOneWidget);
    expect(find.text('Alta'), findsOneWidget);
  });

  testWidgets('sin celdas avisa que no hay reportes en el período', (
    tester,
  ) async {
    await _pump(
      tester,
      _FakeRepo(const HeatMap(cellDeg: 0.005, max: 0, cells: [])),
    );

    expect(find.byKey(const Key('aviso-sin-reportes')), findsOneWidget);
    expect(find.textContaining('Sin reportes'), findsOneWidget);
  });

  testWidgets('con celdas no muestra el aviso de vacío', (tester) async {
    await _pump(tester, _FakeRepo(_conUnaCelda()));

    expect(find.byKey(const Key('aviso-sin-reportes')), findsNothing);
  });

  testWidgets('si falla la carga muestra el error y permite reintentar', (
    tester,
  ) async {
    final repo = _FakeRepo(const ApiFailure.network());
    await _pump(tester, repo);

    expect(find.byKey(const Key('aviso-calor-error')), findsOneWidget);

    repo.respuesta = _conUnaCelda();
    await tester.tap(find.byKey(const Key('reintentar-calor')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('aviso-calor-error')), findsNothing);
    expect(repo.calls, hasLength(2));
  });

  group('al tocar una zona', () {
    testWidgets('muestra "Zona de alta actividad" con su resumen', (
      tester,
    ) async {
      await _pump(tester, _FakeRepo(_conUnaCelda()));

      await _tapAt(tester, tester.getCenter(find.byType(FlutterMap)));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('zona-actividad')), findsOneWidget);
      expect(find.text('Zona de alta actividad'), findsOneWidget);
      expect(
        find.text('7 reportes en 24 h · 5 robos, 2 peleas'),
        findsOneWidget,
      );
      expect(find.text('Más frecuente: 18:00 – 21:00'), findsOneWidget);
    });

    testWidgets('la ventana elegida aparece en el resumen', (tester) async {
      await _pump(tester, _FakeRepo(_conUnaCelda()));
      await tester.tap(find.byKey(const Key('chip-ventana-7d')));
      await tester.pumpAndSettle();

      await _tapAt(tester, tester.getCenter(find.byType(FlutterMap)));
      await tester.pumpAndSettle();

      expect(find.textContaining('reportes en 7 días'), findsOneWidget);
    });

    testWidgets('con 1 reporte el cuadro no habla de "alta actividad"', (
      tester,
    ) async {
      await _pump(tester, _FakeRepo(_conUnaCelda(count: 1)));

      await _tapAt(tester, tester.getCenter(find.byType(FlutterMap)));

      expect(find.text('Reporte en esta zona'), findsOneWidget);
      expect(find.text('Zona de alta actividad'), findsNothing);
    });

    testWidgets('un solo reporte usa el singular', (tester) async {
      final repo = _FakeRepo(
        const HeatMap(
          cellDeg: 0.005,
          max: 1,
          cells: [
            HeatCell(
              position: _centro,
              count: 1,
              tipos: {IncidentType.robo: 1},
              franjaDesde: 9,
              franjaHasta: 12,
            ),
          ],
        ),
      );
      await _pump(tester, repo);

      await _tapAt(tester, tester.getCenter(find.byType(FlutterMap)));
      await tester.pumpAndSettle();

      expect(find.text('1 reporte en 24 h · 1 robo'), findsOneWidget);
    });

    testWidgets('tocar fuera de toda zona no muestra nada', (tester) async {
      await _pump(tester, _FakeRepo(_conUnaCelda()));

      final map = find.byType(FlutterMap);
      await _tapAt(tester, tester.getTopLeft(map) + const Offset(20, 1100));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('zona-actividad')), findsNothing);
    });

    testWidgets('tocar otra vez fuera cierra el cuadro', (tester) async {
      await _pump(tester, _FakeRepo(_conUnaCelda()));
      final map = find.byType(FlutterMap);
      await _tapAt(tester, tester.getCenter(map));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('zona-actividad')), findsOneWidget);

      await _tapAt(tester, tester.getTopLeft(map) + const Offset(20, 1100));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('zona-actividad')), findsNothing);
    });

    testWidgets('"Ver incidentes" cierra la pantalla devolviendo el centro', (
      tester,
    ) async {
      final outcome = await _pump(tester, _FakeRepo(_conUnaCelda()));
      await _tapAt(tester, tester.getCenter(find.byType(FlutterMap)));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('ver-incidentes')));
      await tester.pumpAndSettle();

      expect(outcome.closed, isTrue);
      expect(outcome.value, _centro);
    });
  });

  testWidgets('"Mapa" vuelve sin devolver nada', (tester) async {
    final outcome = await _pump(tester, _FakeRepo(_conUnaCelda()));

    await tester.tap(find.byKey(const Key('boton-volver-mapa')));
    await tester.pumpAndSettle();

    expect(outcome.closed, isTrue);
    expect(outcome.value, isNull);
  });

  testWidgets('los botones + y − cambian el zoom', (tester) async {
    await _pump(tester, _FakeRepo(_conUnaCelda()));
    final controller = tester
        .widget<FlutterMap>(find.byType(FlutterMap))
        .mapController!;
    final inicial = controller.camera.zoom;

    await tester.tap(find.byKey(const Key('zoom-mas')));
    await tester.pumpAndSettle();
    expect(controller.camera.zoom, greaterThan(inicial));

    await tester.tap(find.byKey(const Key('zoom-menos')));
    await tester.tap(find.byKey(const Key('zoom-menos')));
    await tester.pumpAndSettle();
    expect(controller.camera.zoom, lessThan(inicial));
  });
}
