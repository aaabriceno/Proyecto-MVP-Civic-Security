import 'package:civic_security/core/location/location_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('accuracyFrom (precisión informada por el sistema)', () {
    test('un valor positivo se conserva', () {
      expect(accuracyFrom(12.5), 12.5);
      expect(accuracyFrom(350), 350);
    });

    test('0 significa "no sé" (Android lo informa así): no hay precisión', () {
      expect(accuracyFrom(0), isNull);
    });

    test('negativo, NaN o infinito no son una precisión válida', () {
      expect(accuracyFrom(-5), isNull);
      expect(accuracyFrom(double.nan), isNull);
      expect(accuracyFrom(double.infinity), isNull);
    });
  });
}
