import 'package:civic_security/features/profile/presentation/profile_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('initialsOf', () {
    test('toma la inicial de las dos primeras partes del alias', () {
      expect(initialsOf('Halcon-Misti-482'), 'HM');
      expect(initialsOf('zorro_andino'), 'ZA');
      expect(initialsOf('lobo.de.mar'), 'LD');
    });

    test('con una sola parte, sus dos primeras letras', () {
      expect(initialsOf('Cocodrilo66'), 'CO');
      expect(initialsOf('Yo'), 'YO');
    });

    test('con una sola letra, esa letra', () {
      expect(initialsOf('X'), 'X');
    });

    test('ignora separadores repetidos o al borde', () {
      expect(initialsOf('--Halcon--Misti--'), 'HM');
    });

    test('siempre en mayúscula', () {
      expect(initialsOf('ana-lopez'), 'AL');
    });

    test('un alias vacío da un signo de interrogación', () {
      expect(initialsOf(''), '?');
      expect(initialsOf('---'), '?');
    });
  });

  group('monthYear', () {
    test('mes abreviado en castellano y año', () {
      expect(monthYear(DateTime(2026, 9)), 'sep. 2026');
      expect(monthYear(DateTime(2026, 11)), 'nov. 2026');
    });

    test('los doce meses', () {
      const esperado = [
        'ene.',
        'feb.',
        'mar.',
        'abr.',
        'may.',
        'jun.',
        'jul.',
        'ago.',
        'sep.',
        'oct.',
        'nov.',
        'dic.',
      ];
      for (var m = 1; m <= 12; m++) {
        expect(monthYear(DateTime(2027, m)), '${esperado[m - 1]} 2027');
      }
    });
  });
}
