import 'package:civic_security/features/heat/domain/heat_map.dart';
import 'package:civic_security/features/heat/presentation/heat_style.dart';
import 'package:civic_security/features/incident/domain/incident.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

HeatCell _cell(Map<IncidentType, int> tipos, {int? count}) => HeatCell(
  position: const LatLng(-16.4, -71.5),
  count: count ?? tipos.values.fold(0, (a, b) => a + b),
  tipos: tipos,
  franjaDesde: 18,
  franjaHasta: 21,
);

void main() {
  group('heatColor', () {
    test('va de amarillo (baja) a rojo (alta) pasando por naranja', () {
      final baja = HSVColor.fromColor(heatColor(0));
      final media = HSVColor.fromColor(heatColor(0.5));
      final alta = HSVColor.fromColor(heatColor(1));

      // El tono baja de amarillo (~48°) a rojo (~0°)
      expect(baja.hue, greaterThan(media.hue));
      expect(media.hue, greaterThan(alta.hue));
      expect(alta.hue, lessThan(10));
    });

    test('valores fuera de 0 a 1 se recortan', () {
      expect(heatColor(-5), heatColor(0));
      expect(heatColor(7), heatColor(1));
    });
  });

  group('heatCircles', () {
    test('tres círculos por celda, en metros, del más grande al más chico', () {
      final data = HeatMap(
        cellDeg: 0.005,
        max: 8,
        cells: [
          _cell({IncidentType.robo: 8}),
        ],
      );

      final circles = heatCircles(data);

      expect(circles, hasLength(3));
      expect(circles.every((c) => c.useRadiusInMeter), isTrue);
      final radios = [for (final c in circles) c.radius];
      expect(radios[0], greaterThan(radios[1]));
      expect(radios[1], greaterThan(radios[2]));
      // El círculo exterior es de alrededor de una celda (0,005° ~ 556 m)
      expect(radios[0], closeTo(0.005 * 111320 * heatOuterFactor, 0.01));
    });

    test('el centro se vuelve más opaco hacia adentro', () {
      final circles = heatCircles(
        HeatMap(
          cellDeg: 0.005,
          max: 8,
          cells: [
            _cell({IncidentType.robo: 8}),
          ],
        ),
      );

      final alphas = [for (final c in circles) c.color.a];
      expect(alphas[0], lessThan(alphas[1]));
      expect(alphas[1], lessThan(alphas[2]));
    });

    test('las celdas más activas se dibujan encima de las menos activas', () {
      final fria = _cell({IncidentType.robo: 1});
      final caliente = const HeatCell(
        position: LatLng(-16.41, -71.51),
        count: 9,
        tipos: {IncidentType.robo: 9},
        franjaDesde: 0,
        franjaHasta: 3,
      );
      // El servidor las manda de más a menos activa; se pintan al revés
      final circles = heatCircles(
        HeatMap(cellDeg: 0.005, max: 9, cells: [caliente, fria]),
      );

      expect(circles.first.point, fria.position);
      expect(circles.last.point, caliente.position);
    });

    test('la celda elegida lleva borde', () {
      final cell = _cell({IncidentType.robo: 3});
      final data = HeatMap(cellDeg: 0.005, max: 3, cells: [cell]);

      final sin = heatCircles(data);
      final con = heatCircles(data, selected: cell);

      expect(sin.every((c) => c.borderStrokeWidth == 0), isTrue);
      expect(con.first.borderStrokeWidth, greaterThan(0));
    });

    test('sin celdas no hay círculos', () {
      expect(
        heatCircles(const HeatMap(cellDeg: 0.005, max: 0, cells: [])),
        isEmpty,
      );
    });
  });

  group('zoneTitle', () {
    test('no exagera: solo 5 o más reportes son "alta actividad"', () {
      expect(zoneTitle(1), 'Reporte en esta zona');
      expect(zoneTitle(2), 'Zona con actividad');
      expect(zoneTitle(4), 'Zona con actividad');
      expect(zoneTitle(5), 'Zona de alta actividad');
      expect(zoneTitle(25), 'Zona de alta actividad');
    });
  });

  group('zoneSummary', () {
    test('cuenta reportes y tipos, del más al menos frecuente', () {
      final cell = _cell({IncidentType.peleaColegio: 2, IncidentType.robo: 5});

      expect(
        zoneSummary(cell, HeatWindow.day),
        '7 reportes en 24 h · 5 robos, 2 peleas',
      );
    });

    test('usa el singular con uno', () {
      expect(
        zoneSummary(_cell({IncidentType.robo: 1}), HeatWindow.day),
        '1 reporte en 24 h · 1 robo',
      );
    });

    test('la ventana se escribe según cuál sea', () {
      final cell = _cell({IncidentType.robo: 2});

      expect(zoneSummary(cell, HeatWindow.hour), contains('en la última hora'));
      expect(zoneSummary(cell, HeatWindow.week), contains('en 7 días'));
    });

    test('los plurales de cada tipo', () {
      String de(IncidentType t, int n) =>
          zoneSummary(_cell({t: n}), HeatWindow.day).split(' · ').last;

      expect(de(IncidentType.agresionMujer, 1), '1 agresión a mujer');
      expect(de(IncidentType.agresionMujer, 2), '2 agresiones a mujeres');
      expect(de(IncidentType.maltratoAnimal, 2), '2 maltratos animales');
      expect(
        de(IncidentType.actividadSospechosa, 2),
        '2 actividades sospechosas',
      );
      expect(de(IncidentType.otro, 2), '2 otros');
    });

    test('con empate en cantidad, el orden es el de los tipos', () {
      final cell = _cell({IncidentType.otro: 2, IncidentType.robo: 2});

      expect(zoneSummary(cell, HeatWindow.day), endsWith('2 robos, 2 otros'));
    });

    test('sin detalle por tipo solo dice la cuenta', () {
      final cell = _cell({}, count: 3);

      expect(zoneSummary(cell, HeatWindow.day), '3 reportes en 24 h');
    });
  });
}
