import 'package:civic_security/features/auth/domain/password_strength.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('passwordStrengthOf (mide el largo, como pide el servidor)', () {
    test('vacía', () {
      expect(passwordStrengthOf(''), PasswordStrength.empty);
    });

    test('menos de 8 caracteres es muy corta', () {
      expect(passwordStrengthOf('a'), PasswordStrength.veryShort);
      expect(passwordStrengthOf('1234567'), PasswordStrength.veryShort);
    });

    test('de 8 a 11 caracteres todavía no alcanza el mínimo', () {
      expect(passwordStrengthOf('12345678'), PasswordStrength.short);
      expect(passwordStrengthOf('12345678901'), PasswordStrength.short);
    });

    test('desde 12 caracteres es aceptable (el mínimo del servidor)', () {
      expect(passwordStrengthOf('123456789012'), PasswordStrength.acceptable);
      expect(
        passwordStrengthOf('1234567890123456'.substring(0, 15)),
        PasswordStrength.acceptable,
      );
    });

    test('desde 16 caracteres es buena', () {
      expect(passwordStrengthOf('1234567890123456'), PasswordStrength.good);
      expect(
        passwordStrengthOf('mi gato come pescado en la plaza'),
        PasswordStrength.good,
      );
    });

    test('cuenta caracteres y no bytes: una ñ o un emoji valen uno', () {
      // 11 caracteres pero más de 12 bytes: sigue sin alcanzar el mínimo
      expect(
        passwordStrengthOf('ñañañañañaña'.substring(0, 11)),
        PasswordStrength.short,
      );
      expect(passwordStrengthOf('😀' * 12), PasswordStrength.acceptable);
    });

    test('los espacios cuentan: una frase larga vale más que una palabra', () {
      expect(passwordStrengthOf('uno dos tres'), PasswordStrength.acceptable);
    });

    test('solo desde "aceptable" se cumple el mínimo para enviar', () {
      expect(PasswordStrength.short.meetsMinimum, isFalse);
      expect(PasswordStrength.acceptable.meetsMinimum, isTrue);
      expect(PasswordStrength.good.meetsMinimum, isTrue);
    });

    test('segmentos del medidor: 0, 1, 2, 3 y 4', () {
      expect(PasswordStrength.values.map((s) => s.segments).toList(), [
        0,
        1,
        2,
        3,
        4,
      ]);
    });
  });
}
