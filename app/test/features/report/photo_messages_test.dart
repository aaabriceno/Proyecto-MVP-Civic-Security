import 'package:civic_security/core/network/api_failure.dart';
import 'package:civic_security/features/report/presentation/photo_messages.dart';
import 'package:flutter_test/flutter_test.dart';

ApiFailure _f(String code) =>
    ApiFailure(code: code, message: 'texto del servidor');

void main() {
  group('photoFailureMessage', () {
    test('nunca muestra el texto del servidor', () {
      for (final code in [
        'network',
        'photo_has_metadata',
        'cualquiera',
        'http_502',
      ]) {
        expect(
          photoFailureMessage(_f(code)),
          isNot(contains('texto del servidor')),
        );
      }
    });

    test('cada caso conocido tiene su mensaje', () {
      expect(photoFailureMessage(_f('network')), contains('conexión'));
      expect(photoFailureMessage(_f('photo_too_large')), contains('pesada'));
      expect(
        photoFailureMessage(_f('photo_has_metadata')),
        contains('No pudimos usar'),
      );
      expect(
        photoFailureMessage(_f('invalid_photo')),
        contains('No pudimos usar'),
      );
      expect(
        photoFailureMessage(_f('storage_unavailable')),
        contains('de nuevo'),
      );
      expect(
        photoFailureMessage(_f('algo_raro')),
        contains('No pudimos subir la foto'),
      );
    });
  });

  group('canRetryPhoto', () {
    test('se puede reintentar lo que pudo ser pasajero', () {
      for (final code in [
        'network',
        'storage_unavailable',
        'server_busy',
        'rate_limited',
        'unexpected',
        'invalid_response',
        'http_502',
        'unauthorized',
      ]) {
        expect(canRetryPhoto(_f(code)), isTrue, reason: code);
      }
    });

    test('no sirve reintentar lo que volvería a fallar igual', () {
      for (final code in [
        'photo_has_metadata',
        'invalid_photo',
        'photo_too_large',
        'not_author',
        'not_found',
        'unsupported_media_type',
      ]) {
        expect(canRetryPhoto(_f(code)), isFalse, reason: code);
      }
    });
  });
}
