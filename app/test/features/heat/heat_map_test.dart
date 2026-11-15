import 'package:civic_security/features/heat/domain/heat_map.dart';
import 'package:civic_security/features/incident/domain/incident.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _json({List<Object?>? celdas, Object? max = 7}) => {
  'ventana': '24h',
  'cell_deg': 0.005,
  'max': max,
  'celdas': celdas ?? [_celda()],
};

Map<String, dynamic> _celda({
  double lat = -16.395,
  double lng = -71.535,
  int count = 7,
  Map<String, int> tipos = const {'robo': 5, 'pelea_colegio': 2},
  int desde = 18,
  int hasta = 21,
}) => {
  'lat': lat,
  'lng': lng,
  'count': count,
  'tipos': tipos,
  'franja': {'desde': desde, 'hasta': hasta},
};

void main() {
  group('HeatWindow', () {
    test(
      'cada ventana habla con la API con su valor y se muestra con su rótulo',
      () {
        expect(HeatWindow.hour.wire, '1h');
        expect(HeatWindow.day.wire, '24h');
        expect(HeatWindow.week.wire, '7d');
        expect(HeatWindow.hour.label, 'Última hora');
        expect(HeatWindow.day.label, '24 h');
        expect(HeatWindow.week.label, '7 días');
      },
    );

    test('el orden es de la más corta a la más larga', () {
      expect(HeatWindow.values, [
        HeatWindow.hour,
        HeatWindow.day,
        HeatWindow.week,
      ]);
    });
  });

  group('HeatMap.fromJson', () {
    test('convierte la respuesta de la API', () {
      final map = HeatMap.fromJson(_json());

      expect(map.cellDeg, 0.005);
      expect(map.max, 7);
      expect(map.cells, hasLength(1));

      final cell = map.cells.single;
      expect(cell.position.latitude, -16.395);
      expect(cell.position.longitude, -71.535);
      expect(cell.count, 7);
      expect(cell.tipos, {IncidentType.robo: 5, IncidentType.peleaColegio: 2});
      expect(cell.franjaDesde, 18);
      expect(cell.franjaHasta, 21);
    });

    test('lat y lng llegan por separado y LatLng pide lat primero', () {
      final cell = HeatMap.fromJson(
        _json(celdas: [_celda(lat: -16.4, lng: -71.5)]),
      ).cells.single;

      expect(cell.position.latitude, -16.4);
      expect(cell.position.longitude, -71.5);
    });

    test('sin celdas: lista vacía y max 0', () {
      final map = HeatMap.fromJson(_json(celdas: [], max: 0));

      expect(map.cells, isEmpty);
      expect(map.max, 0);
    });

    test('un tipo que esta versión no conoce se ignora, no rompe', () {
      final cell = HeatMap.fromJson(
        _json(
          celdas: [
            _celda(tipos: {'robo': 2, 'tipo_nuevo': 9}),
          ],
        ),
      ).cells.single;

      expect(cell.tipos, {IncidentType.robo: 2});
    });

    test('una respuesta malformada lanza FormatException', () {
      for (final malo in <Object?>[
        null,
        'texto',
        <String, dynamic>{},
        {..._json(), 'celdas': 'no es lista'},
        {..._json(), 'cell_deg': 'x'},
        _json(celdas: [<String, dynamic>{}]),
        _json(celdas: [_celda()..remove('franja')]),
        _json(celdas: ['no es mapa']),
      ]) {
        expect(
          () => HeatMap.fromJson(malo),
          throwsA(isA<FormatException>()),
          reason: '$malo',
        );
      }
    });
  });

  group('HeatCell', () {
    test('la intensidad es relativa a la celda más activa, con un piso', () {
      HeatCell cell(int n) => HeatMap.fromJson(
        _json(
          celdas: [_celda(count: n)],
          max: n,
        ),
      ).cells.single;

      // Con pocas celdas un reporte solo no debe verse como "intensidad máxima"
      expect(HeatMap.intensity(count: 1, max: 1), lessThan(0.5));
      expect(HeatMap.intensity(count: 8, max: 8), 1.0);
      expect(HeatMap.intensity(count: 4, max: 8), 0.5);
      expect(HeatMap.intensity(count: 0, max: 0), 0.0);
      expect(cell(3).count, 3);
    });

    test('la franja se escribe como "18:00 – 21:00"', () {
      final cell = HeatMap.fromJson(_json()).cells.single;

      expect(cell.franjaLabel, '18:00 – 21:00');
    });

    test('la franja de madrugada lleva el cero a la izquierda', () {
      final cell = HeatMap.fromJson(
        _json(celdas: [_celda(desde: 0, hasta: 3)]),
      ).cells.single;

      expect(cell.franjaLabel, '00:00 – 03:00');
    });

    test('la última franja termina a las 24:00', () {
      final cell = HeatMap.fromJson(
        _json(celdas: [_celda(desde: 21, hasta: 24)]),
      ).cells.single;

      expect(cell.franjaLabel, '21:00 – 24:00');
    });
  });
}
