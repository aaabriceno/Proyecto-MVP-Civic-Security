// Prueba de rendimiento del mapa en un dispositivo REAL, en modo profile.
//
//   flutter drive \
//     --driver=test_driver/perf_driver.dart \
//     --target=integration_test/map_perf_test.dart \
//     --profile -d <id del dispositivo>
//
// Arrastra el mapa de ida y vuelta y registra cuánto tarda cada cuadro. Los
// resultados quedan en `build/<escenario>.timeline_summary.json`.
//
// Cómo leerlos (a 60 Hz cada cuadro dispone de 16,6 ms):
//   * frame_build_time_*       -> hilo de interfaz (construir widgets).
//   * frame_rasterizer_time_*  -> hilo de dibujo (pintar con la GPU).
//   * missed_frame_*_budget_count -> cuadros que pasaron de 16,6 ms.
// Si el cuello de botella está en el dibujo, simplificar widgets no ayuda; si
// está en la interfaz, sí.
//
// No sale a la red salvo para las teselas del mapa; los incidentes son
// sintéticos y el tiempo real está apagado, para que la medición sea repetible.
import 'dart:math';

import 'package:civic_security/core/location/location_service.dart';
import 'package:civic_security/features/incident/data/incident_repository.dart';
import 'package:civic_security/features/incident/domain/incident.dart';
import 'package:civic_security/features/map/data/incident_stream.dart';
import 'package:civic_security/features/map/presentation/map_screen.dart';
import 'package:civic_security/features/report/domain/new_incident.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:latlong2/latlong.dart';

import '../test/features/map/fake_incident_stream.dart';

/// Sin ubicación: el mapa abre mostrando toda Arequipa y no aparece el diálogo
/// de permisos del sistema (que una prueba automática no puede contestar).
class _SinUbicacion implements LocationService {
  @override
  Future<LocationState> locate() async =>
      const LocationUnavailable(LocationFailure.denied);

  @override
  Stream<LocationFound> watch() => const Stream.empty();

  @override
  Future<void> openSettingsFor(LocationFailure reason) async {}
}

class _Repositorio implements IncidentRepository {
  _Repositorio(this.incidentes);

  final List<Incident> incidentes;

  @override
  Future<Incident> create(
    NewIncident input, {
    required String idempotencyKey,
  }) => throw UnimplementedError();

  @override
  Future<List<Incident>> fetchSnapshot(Bbox bbox) async => incidentes;
}

/// [cantidad] incidentes repartidos como en los datos de siembra: agrupados
/// alrededor del centro de Arequipa. Siempre los mismos (semilla fija).
List<Incident> _incidentes(int cantidad) {
  final azar = Random(2026);
  return [
    for (var i = 0; i < cantidad; i++)
      Incident(
        id: '00000000-0000-4000-8000-${i.toString().padLeft(12, '0')}',
        tipo: IncidentType.values[i % IncidentType.values.length],
        descripcion: i.isEven ? 'Reporte de prueba $i' : null,
        position: LatLng(
          -16.395 + (azar.nextDouble() - 0.5) * 0.09,
          -71.530 + (azar.nextDouble() - 0.5) * 0.09,
        ),
        estado: IncidentStatus.values[i % IncidentStatus.values.length],
        creadoEn: DateTime.now().toUtc().subtract(
          Duration(minutes: 1 + azar.nextInt(1200)),
        ),
      ),
  ];
}

/// Arrastra el mapa de ida y vuelta, con pausas, como lo haría una persona.
Future<void> _arrastrar(WidgetTester tester, {required int veces}) async {
  final mapa = find.byType(FlutterMap);
  for (var i = 0; i < veces; i++) {
    await tester.timedDrag(
      mapa,
      const Offset(-180, 120),
      const Duration(milliseconds: 500),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.timedDrag(
      mapa,
      const Offset(180, -120),
      const Duration(milliseconds: 500),
    );
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Dibuja a la velocidad real del dispositivo, como en la app instalada
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  Future<void> medir(
    WidgetTester tester, {
    required String escenario,
    required int incidentes,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          locationServiceProvider.overrideWithValue(_SinUbicacion()),
          incidentRepositoryProvider.overrideWithValue(
            _Repositorio(_incidentes(incidentes)),
          ),
          incidentStreamProvider.overrideWithValue(FakeIncidentStream()),
        ],
        // Directo al mapa: la app real arranca en la puerta de inicio de sesión
        // y una prueba automática no tiene cuenta. Aquí solo importa el mapa.
        child: const MaterialApp(home: MapScreen()),
      ),
    );
    // Deja cargar las teselas y el snapshot
    await tester.pump(const Duration(seconds: 4));

    // Calentamiento: el primer paso descarga teselas y compila shaders, y eso
    // no es lo que queremos medir
    await _arrastrar(tester, veces: 2);

    await binding.traceAction(
      () => _arrastrar(tester, veces: 6),
      reportKey: escenario,
      // Solo los eventos de cuadros (interfaz y dibujo). Con 'all' el
      // registro de la VM se llena en medio segundo cuando hay muchos widgets y
      // descarta casi todos los cuadros: el resumen saldría de unos pocos.
      streams: const ['Dart', 'Embedder'],
    );
  }

  // De menos a más pines: sirve para ver cuánto margen queda al crecer los
  // reportes. El de 0 pines es el control (solo teselas).
  var n = 0;
  for (final incidentes in [0, 80, 300, 600]) {
    final posicion = ++n;
    testWidgets('$posicion. arrastrar el mapa con $incidentes pines', (
      tester,
    ) async {
      await medir(
        tester,
        escenario: '${posicion}_mapa_${incidentes}_pines',
        incidentes: incidentes,
      );
    });
  }
}
