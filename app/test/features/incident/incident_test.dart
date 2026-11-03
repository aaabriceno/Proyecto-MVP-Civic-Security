import 'package:civic_security/features/incident/domain/incident.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

Map<String, dynamic> _json({
  String tipo = 'robo',
  String estado = 'sin_verificar',
  String? descripcion = 'Me robaron el celular',
}) => {
  'id': 'f92c3305-b156-4ceb-a7c1-9f101f3d0c7b',
  'tipo': tipo,
  'descripcion': descripcion,
  'lat': -16.3963,
  'lng': -71.534,
  'estado': estado,
  'creado_en': '2026-11-03T21:50:33.997686Z',
};

void main() {
  group('Incident.tryFromJson', () {
    test('lee lat y lng sin invertirlos', () {
      final i = Incident.tryFromJson(_json())!;
      expect(i.position, const LatLng(-16.3963, -71.534));
    });

    test('lee tipo, estado, descripción y fecha en UTC', () {
      final i = Incident.tryFromJson(_json())!;
      expect(i.tipo, IncidentType.robo);
      expect(i.estado, IncidentStatus.sinVerificar);
      expect(i.descripcion, 'Me robaron el celular');
      expect(i.creadoEn, DateTime.utc(2026, 11, 3, 21, 50, 33, 997, 686));
      expect(i.creadoEn.isUtc, isTrue);
    });

    test('acepta descripción null', () {
      expect(
        Incident.tryFromJson(_json(descripcion: null))!.descripcion,
        isNull,
      );
    });

    test('un tipo o estado desconocido (backend más nuevo) se omite', () {
      expect(Incident.tryFromJson(_json(tipo: 'ovni')), isNull);
      expect(Incident.tryFromJson(_json(estado: 'archivado')), isNull);
    });

    test('un JSON malformado lanza FormatException', () {
      final malo = _json()..remove('lat');
      expect(() => Incident.tryFromJson(malo), throwsFormatException);
    });
  });

  group('IncidentType', () {
    test('fromWire usa los valores de la API', () {
      expect(
        IncidentType.fromWire('agresion_mujer'),
        IncidentType.agresionMujer,
      );
      expect(
        IncidentType.fromWire('maltrato_animal'),
        IncidentType.maltratoAnimal,
      );
      expect(IncidentType.fromWire('pelea_colegio'), IncidentType.peleaColegio);
      expect(
        IncidentType.fromWire('actividad_sospechosa'),
        IncidentType.actividadSospechosa,
      );
      expect(IncidentType.fromWire('otro'), IncidentType.otro);
      expect(IncidentType.fromWire('ovni'), isNull);
    });

    test('cada tipo tiene la etiqueta del producto', () {
      expect(IncidentType.robo.label, 'Robo');
      expect(IncidentType.agresionMujer.label, 'Agresión a mujer');
      expect(IncidentType.maltratoAnimal.label, 'Maltrato animal');
      expect(IncidentType.peleaColegio.label, 'Pelea en salida de colegio');
      expect(IncidentType.actividadSospechosa.label, 'Actividad sospechosa');
      expect(IncidentType.otro.label, 'Otro');
    });

    test('wire y fromWire son inversos', () {
      for (final t in IncidentType.values) {
        expect(IncidentType.fromWire(t.wire), t);
      }
    });
  });

  group('Bbox', () {
    test('toQuery respeta el orden de la API: minLng,minLat,maxLng,maxLat', () {
      const b = Bbox(
        minLng: -71.54,
        minLat: -16.4,
        maxLng: -71.53,
        maxLat: -16.39,
      );
      expect(b.toQuery(), '-71.540000,-16.400000,-71.530000,-16.390000');
    });

    test('nunca usa notación científica, que el backend no esperaría', () {
      const b = Bbox(
        minLng: -0.0000001,
        minLat: -0.0000002,
        maxLng: 0.0000001,
        maxLat: 0.0000002,
      );
      expect(b.toQuery(), isNot(contains('e')));
    });

    test('fromCorners recorta a rangos válidos', () {
      final b = Bbox.fromCorners(south: -95, west: -200, north: 95, east: 200);
      expect(
        (b.minLat, b.minLng, b.maxLat, b.maxLng),
        (-90.0, -180.0, 90.0, 180.0),
      );
    });
  });
}
