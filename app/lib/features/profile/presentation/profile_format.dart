/// Las iniciales para el avatar: la primera letra de las dos primeras partes del
/// alias (`Halcon-Misti-482` -> `HM`). Con una sola parte, sus dos primeras
/// letras (`Cocodrilo66` -> `CO`). Siempre en mayúscula.
String initialsOf(String alias) {
  final parts = alias
      .split(RegExp(r'[-_.]'))
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '?';

  final text = parts.length >= 2
      ? '${parts[0][0]}${parts[1][0]}'
      : (parts[0].length >= 2 ? parts[0].substring(0, 2) : parts[0]);
  return text.toUpperCase();
}

const _meses = [
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

/// "sep. 2026".
String monthYear(DateTime date) => '${_meses[date.month - 1]} ${date.year}';
