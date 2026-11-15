import 'dart:io';
import 'dart:typed_data';

/// Lee una foto de prueba de `test/fixtures/photos/`.
Uint8List photoFixture(String name) =>
    File('test/fixtures/photos/$name').readAsBytesSync();

/// La misma regla que aplica el servidor (`Civic.Evidence.Jpeg`): un JPEG solo
/// puede llevar los segmentos necesarios para dibujar la imagen y un JFIF mínimo.
/// Cualquier otro segmento (EXIF, XMP, ICC, IPTC, comentarios...) es un
/// metadato escondido.
///
/// Devuelve `null` si la foto es limpia, o qué tiene de malo.
String? jpegProblem(Uint8List b) {
  if (b.length < 4 || b[0] != 0xFF || b[1] != 0xD8) return 'no es un JPEG';
  var i = 2;
  var hasFrame = false;
  var scans = 0;

  while (i < b.length) {
    if (b[i] != 0xFF) return 'se esperaba un marcador en $i';
    while (i + 1 < b.length && b[i + 1] == 0xFF) {
      i++;
    }
    if (i + 1 >= b.length) return 'cortada';
    final marker = b[i + 1];

    if (marker == 0xD9) {
      if (i + 2 != b.length) return 'datos después del final';
      return hasFrame && scans > 0 ? null : 'sin imagen';
    }

    if (marker >= 0xD0 && marker <= 0xD7 || marker == 0x01) {
      i += 2;
      continue;
    }

    if (i + 4 > b.length) return 'cortada';
    final length = (b[i + 2] << 8) | b[i + 3];
    if (length < 2 || i + 2 + length > b.length) return 'segmento mal formado';
    final payload = b.sublist(i + 4, i + 2 + length);

    if (marker >= 0xC0 && marker <= 0xC2) {
      hasFrame = true;
    } else if (marker == 0xE0) {
      final jfif =
          payload.length == 14 &&
          String.fromCharCodes(payload.sublist(0, 4)) == 'JFIF' &&
          payload[12] == 0 &&
          payload[13] == 0;
      if (!jfif) return 'APP0 que no es un JFIF mínimo';
    } else if (marker == 0xC4 || marker == 0xDB || marker == 0xDD) {
      // tablas: no llevan datos del usuario
    } else if (marker == 0xDA) {
      scans++;
      i += 2 + length;
      // datos comprimidos: hasta el siguiente marcador de verdad
      while (i + 1 < b.length) {
        if (b[i] == 0xFF &&
            b[i + 1] != 0x00 &&
            !(b[i + 1] >= 0xD0 && b[i + 1] <= 0xD7)) {
          break;
        }
        i++;
      }
      continue;
    } else {
      return 'segmento ${marker.toRadixString(16)} (metadatos)';
    }
    i += 2 + length;
  }
  return 'sin final de imagen';
}

/// ¿Aparece [text] dentro de [bytes]? (como texto, sin importar dónde)
bool containsText(Uint8List bytes, String text) {
  final needle = text.codeUnits;
  outer:
  for (var i = 0; i + needle.length <= bytes.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (bytes[i + j] != needle[j]) continue outer;
    }
    return true;
  }
  return false;
}
