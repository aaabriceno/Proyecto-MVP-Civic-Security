import 'dart:typed_data';

import 'package:civic_security/core/media/photo_processor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import '../support/jpeg_structure.dart';

void main() {
  late Uint8List sucia;

  setUpAll(() => sucia = photoFixture('sucia.jpg'));

  group(
    'la foto de partida es de verdad una foto sucia (la prueba no es vacía)',
    () {
      test('trae GPS, modelo, serie, XMP, perfil de color y comentario', () {
        for (final secreto in [
          'Exif',
          'TB350XU',
          'HVA5KEYM',
          'Fulano Perez',
          'Mercaderes',
          'ICC_PROFILE',
        ]) {
          expect(containsText(sucia, secreto), isTrue, reason: secreto);
        }
        expect(jpegProblem(sucia), isNotNull);
      });
    },
  );

  group('preparePhotoSync: quita los metadatos', () {
    test('devuelve un JPEG que el servidor aceptaría', () {
      final out = preparePhotoSync(sucia);

      expect(out[0], 0xFF);
      expect(out[1], 0xD8);
      expect(jpegProblem(out), isNull);
    });

    test(
      'no queda ni rastro del GPS, el modelo, la serie, el autor ni el comentario',
      () {
        final out = preparePhotoSync(sucia);

        for (final secreto in [
          'Exif',
          'GPS',
          'Lenovo',
          'TB350XU',
          'HVA5KEYM',
          'Fulano',
          'Mercaderes',
          'xap',
          'ICC_PROFILE',
          'ICC_PROFILE',
        ]) {
          expect(containsText(out, secreto), isFalse, reason: secreto);
        }
      },
    );

    test('también limpia un PNG y una foto chica', () {
      expect(
        jpegProblem(preparePhotoSync(photoFixture('con_transparencia.png'))),
        isNull,
      );
      expect(jpegProblem(preparePhotoSync(photoFixture('chica.jpg'))), isNull);
    });

    test('procesar lo ya procesado sigue dando una foto limpia', () {
      final una = preparePhotoSync(sucia);

      expect(jpegProblem(preparePhotoSync(una)), isNull);
    });

    test('no modifica los bytes originales', () {
      final copia = Uint8List.fromList(sucia);

      preparePhotoSync(sucia);

      expect(sucia, copia);
    });
  });

  group('preparePhotoSync: la imagen', () {
    test('aplica la rotación guardada en los metadatos antes de borrarlos', () {
      // La original mide 2400x1800 y dice "girar 90° a la derecha"
      final out = img.decodeJpg(preparePhotoSync(sucia))!;

      expect(out.height, greaterThan(out.width), reason: 'quedó de pie');
    });

    test(
      'el rojo (arriba a la izquierda) pasa arriba a la derecha y el azul abajo a la izquierda',
      () {
        final out = img.decodeJpg(preparePhotoSync(sucia))!;
        // Con 90° a la derecha, el punto (x, y) pasa a (alto-1-y, x); luego se
        // reduce de 1800 a 960 de ancho (factor 0,5333)
        final rojo = out.getPixel(733, 293);
        final azul = out.getPixel(186, 1067);

        expect([rojo.r > 200, rojo.g < 90, rojo.b < 90], everyElement(isTrue));
        expect([azul.r < 90, azul.g < 90, azul.b > 200], everyElement(isTrue));
      },
    );

    test(
      'el lado más largo no pasa de 1280 px y se conserva la proporción',
      () {
        final out = img.decodeJpg(preparePhotoSync(sucia))!;

        expect(out.height, maxPhotoSide);
        expect(out.width, 960);
      },
    );

    test('no agranda una foto chica', () {
      final out = img.decodeJpg(preparePhotoSync(photoFixture('chica.jpg')))!;

      expect((out.width, out.height), (64, 48));
    });

    test('pesa bastante menos que el límite del servidor (2 MB)', () {
      final out = preparePhotoSync(sucia);

      expect(out.length, lessThan(500 * 1024));
    });

    test('un PNG con transparencia queda sobre fondo blanco, no negro', () {
      final out = img.decodeJpg(
        preparePhotoSync(photoFixture('con_transparencia.png')),
      )!;

      final fondo = out.getPixel(10, 10); // era transparente
      final rojo = out.getPixel(200, 150); // era rojo opaco

      expect([
        fondo.r > 240,
        fondo.g > 240,
        fondo.b > 240,
      ], everyElement(isTrue));
      expect([rojo.r > 200, rojo.g < 90, rojo.b < 90], everyElement(isTrue));
    });
  });

  group('preparePhotoSync: lo que no se puede procesar', () {
    test('algo que no es una imagen', () {
      expect(
        () => preparePhotoSync(photoFixture('no_es_imagen.bin')),
        throwsA(isA<UnreadablePhotoException>()),
      );
    });

    test('una foto cortada', () {
      expect(
        () => preparePhotoSync(photoFixture('truncada.jpg')),
        throwsA(isA<UnreadablePhotoException>()),
      );
    });

    test('un archivo vacío', () {
      expect(
        () => preparePhotoSync(Uint8List(0)),
        throwsA(isA<UnreadablePhotoException>()),
      );
    });

    test('un archivo enorme se rechaza sin ni intentar abrirlo', () {
      expect(
        () => preparePhotoSync(Uint8List(maxPhotoInputBytes + 1)),
        throwsA(isA<PhotoTooLargeException>()),
      );
    });
  });

  test(
    'preparePhoto (en otro hilo) da lo mismo que la versión directa',
    () async {
      expect(await preparePhoto(sucia), preparePhotoSync(sucia));
    },
  );
}
