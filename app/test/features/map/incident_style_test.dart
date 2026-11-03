import 'package:civic_security/features/incident/domain/incident.dart';
import 'package:civic_security/features/map/presentation/incident_style.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 11, 3, 12);

  group('relativeTime', () {
    test('menos de un minuto', () {
      expect(
        relativeTime(now.subtract(const Duration(seconds: 20)), now),
        'Hace un momento',
      );
    });
    test('minutos', () {
      expect(
        relativeTime(now.subtract(const Duration(minutes: 12)), now),
        'Hace 12 min',
      );
    });
    test('horas', () {
      expect(
        relativeTime(now.subtract(const Duration(hours: 5, minutes: 40)), now),
        'Hace 5 h',
      );
    });
    test('días', () {
      expect(
        relativeTime(now.subtract(const Duration(days: 3)), now),
        'Hace 3 d',
      );
    });
    test('una fecha futura (reloj desajustado) no se muestra negativa', () {
      expect(
        relativeTime(now.add(const Duration(minutes: 5)), now),
        'Hace un momento',
      );
    });
  });

  group('formatDistance', () {
    test('metros, redondeados a 10', () {
      expect(formatDistance(304), '300 m');
      expect(formatDistance(7), '10 m');
    });
    test('kilómetros con coma decimal', () {
      expect(formatDistance(1234), '1,2 km');
      expect(formatDistance(12000), '12 km');
    });
  });

  group('estilo por tipo', () {
    test('cada tipo tiene color, ícono y etiqueta corta propios', () {
      final colors = IncidentType.values.map(typeColor).toSet();
      final icons = IncidentType.values.map(typeIcon).toSet();
      expect(colors.length, IncidentType.values.length);
      expect(icons.length, IncidentType.values.length);
      for (final t in IncidentType.values) {
        expect(typeShortLabel(t), isNotEmpty);
      }
    });
  });
}
