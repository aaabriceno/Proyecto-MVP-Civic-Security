import 'package:civic_security/features/incident/domain/incident.dart';
import 'package:civic_security/features/report/domain/new_incident.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('toJson usa los nombres de la API', () {
    const n = NewIncident(
      tipo: IncidentType.agresionMujer,
      descripcion: 'Acoso en la esquina',
      lat: -16.4,
      lng: -71.5,
    );
    expect(n.toJson(), {
      'tipo': 'agresion_mujer',
      'descripcion': 'Acoso en la esquina',
      'lat': -16.4,
      'lng': -71.5,
    });
  });

  test('la descripción se recorta y, si queda vacía, no se envía', () {
    expect(
      const NewIncident(
        tipo: IncidentType.robo,
        descripcion: '  hola  ',
        lat: 1,
        lng: 2,
      ).toJson()['descripcion'],
      'hola',
    );
    for (final vacia in [null, '', '   \n ']) {
      final json = NewIncident(
        tipo: IncidentType.robo,
        descripcion: vacia,
        lat: 1,
        lng: 2,
      ).toJson();
      expect(
        json.containsKey('descripcion'),
        isFalse,
        reason: 'descripción: "$vacia"',
      );
    }
  });

  test(
    'dos reportes con el mismo contenido son iguales (para reusar la clave)',
    () {
      const a = NewIncident(
        tipo: IncidentType.robo,
        descripcion: 'x',
        lat: 1,
        lng: 2,
      );
      const b = NewIncident(
        tipo: IncidentType.robo,
        descripcion: 'x',
        lat: 1,
        lng: 2,
      );
      const c = NewIncident(
        tipo: IncidentType.otro,
        descripcion: 'x',
        lat: 1,
        lng: 2,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    },
  );

  test('descripciones que solo difieren en espacios son el mismo reporte', () {
    const a = NewIncident(
      tipo: IncidentType.robo,
      descripcion: 'x',
      lat: 1,
      lng: 2,
    );
    const b = NewIncident(
      tipo: IncidentType.robo,
      descripcion: '  x ',
      lat: 1,
      lng: 2,
    );
    expect(a, b);
  });
}
