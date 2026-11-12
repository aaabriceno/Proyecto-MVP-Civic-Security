import 'package:flutter/widgets.dart' show StringCharacters;

/// Largo mínimo que exige el servidor (`Civic.Accounts.Password`).
const minPasswordLength = 12;

/// Qué tan larga es una contraseña, para el medidor del registro.
///
/// Solo mide el **largo**, y es a propósito: el servidor sigue la guía NIST
/// 800-63B, que no pide mayúsculas ni símbolos (empujan a contraseñas peores,
/// como "Hola123!") y recomienda frases largas y fáciles de recordar. El orden
/// de los valores importa: [segments] es su posición.
enum PasswordStrength {
  empty,
  veryShort,
  short,
  acceptable,
  good;

  /// Cuántos de los 4 segmentos del medidor se pintan.
  int get segments => index;

  /// ¿Cumple el mínimo del servidor?
  bool get meetsMinimum => this == acceptable || this == good;
}

/// Cuenta caracteres, no bytes: una `ñ` o un emoji valen uno, igual que en el
/// servidor.
PasswordStrength passwordStrengthOf(String password) {
  final length = password.characters.length;
  if (length == 0) return PasswordStrength.empty;
  if (length < 8) return PasswordStrength.veryShort;
  if (length < minPasswordLength) return PasswordStrength.short;
  if (length < 16) return PasswordStrength.acceptable;
  return PasswordStrength.good;
}
