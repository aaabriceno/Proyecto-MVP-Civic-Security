import 'dart:math';

/// Propone un alias al azar para quien se registra: `Halcon-Misti-482`.
///
/// El alias es lo único que se ve de una persona, así que no debe parecerse a
/// su nombre. Elegir uno por ella evita que escriba su nombre o apellido sin
/// pensarlo; si no le gusta, pide otro con "Otro" o lo edita.
///
/// Todas las combinaciones cumplen el formato del servidor (letras sin tilde,
/// guion y números, de 3 a 20 caracteres): el test lo comprueba con el peor
/// caso, así que al agregar palabras hay que respetar que `animal + lugar` no
/// pase de 15 letras.
class AliasSuggester {
  AliasSuggester([Random? random]) : _random = random ?? Random();

  final Random _random;

  static const animals = [
    'Halcon', 'Condor', 'Vicuna', 'Puma', 'Zorro', 'Alpaca', 'Llama', //
    'Lobo', 'Buho', 'Colibri', 'Venado', 'Gavilan', 'Tucan', 'Zorzal',
    'Ocelote', 'Jaguar', 'Guanaco', 'Cuy',
  ];

  static const places = [
    'Misti', 'Chachani', 'Ampato', 'Colca', 'Sillar', 'Campina', 'Cayma', //
    'Sabandia', 'Tingo', 'Socabaya', 'Umacollo', 'Selva', 'Chilina',
    'Congata', 'Charcani', 'Ichu', 'Volcan', 'Sachaca', 'Tiabaya', 'Rocoto',
    'Uchumayo', 'Pocsi', 'Yura', 'Chiguata',
  ];

  /// Un alias nuevo. Si se pasa el [anterior] (el que ya se está mostrando),
  /// el resultado siempre es distinto: "Otro" tiene que cambiar algo.
  String next({String? anterior}) {
    final animal = animals[_random.nextInt(animals.length)];
    final lugar = places[_random.nextInt(places.length)];
    var numero = 100 + _random.nextInt(900);

    var alias = '$animal-$lugar-$numero';
    if (alias == anterior) {
      // Coincidencia (o un generador que repite): se cambia el número y listo
      numero = numero == 999 ? 100 : numero + 1;
      alias = '$animal-$lugar-$numero';
    }
    return alias;
  }
}

/// El formato de alias que acepta el servidor (`Civic.Accounts.User`): letras
/// sin tilde, números, guion, guion bajo y punto, de 3 a 20 caracteres. Sin
/// espacios ni caracteres que se parezcan a otros (homoglifos).
final _aliasFormat = RegExp(r'^[A-Za-z0-9_.-]{3,20}$');

bool isValidAlias(String alias) => _aliasFormat.hasMatch(alias);
