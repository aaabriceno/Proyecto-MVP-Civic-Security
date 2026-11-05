import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

/// Las distancias de referencia salen de PostGIS (`ST_Distance` sobre
/// `geography`), el mismo cálculo que usa el servidor. La app debe coincidir:
/// si la distancia que muestra no cuadra con el mapa, el error no está en la
/// fórmula sino en la ubicación del dispositivo.
void main() {
  const distance = Distance();

  const plaza = LatLng(-16.3989, -71.5370);

  test('Plaza de Armas -> Alto Selva Alegre: 3 208 m según PostGIS', () {
    final m = distance.as(LengthUnit.Meter, plaza, const LatLng(-16.3750, -71.5200));
    expect(m, closeTo(3208, 3));
  });

  test('Plaza de Armas -> UCSP: 431 m según PostGIS', () {
    final m = distance.as(LengthUnit.Meter, plaza, const LatLng(-16.3963, -71.5340));
    expect(m, closeTo(431, 2));
  });

  test('0,0005° de latitud son ~55 m', () {
    final m = distance.as(
      LengthUnit.Meter,
      const LatLng(-16.4300, -71.5050),
      const LatLng(-16.4295, -71.5050),
    );
    expect(m, closeTo(55, 1));
  });

  test('es simétrica y la distancia a uno mismo es 0', () {
    const a = LatLng(-16.40, -71.53);
    const b = LatLng(-16.43, -71.50);
    expect(distance.as(LengthUnit.Meter, a, b), distance.as(LengthUnit.Meter, b, a));
    expect(distance.as(LengthUnit.Meter, a, a), 0);
  });
}
