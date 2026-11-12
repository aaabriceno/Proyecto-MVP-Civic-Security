import 'dart:math';

import 'package:civic_security/features/auth/domain/alias_suggester.dart';
import 'package:flutter_test/flutter_test.dart';

/// El alias que acepta el servidor (ver `Civic.Accounts.User`).
final _formatoDelServidor = RegExp(r'^[A-Za-z0-9_.-]{3,20}$');

void main() {
  group('AliasSuggester', () {
    test('tiene la forma Animal-Lugar-123', () {
      final alias = AliasSuggester(Random(1)).next();

      expect(alias, matches(RegExp(r'^[A-Z][a-z]+-[A-Z][a-z]+-\d{3}$')));
    });

    test('cualquier combinación posible la acepta el servidor', () {
      // El peor caso: las palabras más largas y el número más grande
      final animales = AliasSuggester.animals;
      final lugares = AliasSuggester.places;
      expect(animales, isNotEmpty);
      expect(lugares, isNotEmpty);

      for (final animal in animales) {
        for (final lugar in lugares) {
          final alias = '$animal-$lugar-999';
          expect(
            alias,
            matches(_formatoDelServidor),
            reason: '$alias no cabe en el formato de alias del servidor',
          );
        }
      }
    });

    test(
      'las palabras no llevan tildes ni espacios (el servidor los rechaza)',
      () {
        for (final palabra in [
          ...AliasSuggester.animals,
          ...AliasSuggester.places,
        ]) {
          expect(palabra, matches(RegExp(r'^[A-Z][a-z]+$')), reason: palabra);
        }
      },
    );

    test('con la misma semilla da siempre el mismo alias (repetible)', () {
      expect(
        AliasSuggester(Random(7)).next(),
        AliasSuggester(Random(7)).next(),
      );
    });

    test('"Otro" nunca repite el alias anterior', () {
      // Un generador que siempre elige lo primero: sin la protección, el
      // alias sería idéntico en cada llamada
      final suggester = AliasSuggester(_SiempreCero());
      final primero = suggester.next();

      expect(suggester.next(anterior: primero), isNot(primero));
    });

    test('da bastante variedad (no son 3 o 4 alias repartidos)', () {
      final suggester = AliasSuggester(Random(3));
      final vistos = {for (var i = 0; i < 200; i++) suggester.next()};

      expect(vistos.length, greaterThan(150));
    });
  });
  group('isValidAlias (la misma regla que el servidor)', () {
    test('acepta letras, números, guion, guion bajo y punto, de 3 a 20', () {
      for (final alias in ['abc', 'Halcon-Misti-482', 'a_b.c-d', 'x' * 20]) {
        expect(isValidAlias(alias), isTrue, reason: alias);
      }
    });

    test('rechaza tildes, espacios, símbolos y largos fuera de rango', () {
      for (final alias in [
        '',
        'ab',
        'x' * 21,
        'Cóndor-1',
        'Mi Alias',
        'alias@x',
        'ñandú',
        'a/b',
      ]) {
        expect(isValidAlias(alias), isFalse, reason: alias);
      }
    });
  });
}

class _SiempreCero implements Random {
  @override
  bool nextBool() => false;
  @override
  double nextDouble() => 0;
  @override
  int nextInt(int max) => 0;
}
