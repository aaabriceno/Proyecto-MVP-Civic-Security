import 'package:flutter/material.dart';

import '../../incident/domain/incident.dart';

// Colores e íconos del diseño de Figma (frame 05 – Mapa)
Color typeColor(IncidentType type) => switch (type) {
  IncidentType.robo => const Color(0xFFE53935),
  IncidentType.agresionMujer => const Color(0xFF9B51E0),
  IncidentType.maltratoAnimal => const Color(0xFFF2994A),
  IncidentType.peleaColegio => const Color(0xFF2F80ED),
  IncidentType.actividadSospechosa => const Color(0xFF6B7280),
  IncidentType.otro => const Color(0xFF374151),
};

IconData typeIcon(IncidentType type) => switch (type) {
  IncidentType.robo => Icons.priority_high,
  IncidentType.agresionMujer => Icons.female,
  IncidentType.maltratoAnimal => Icons.pets,
  IncidentType.peleaColegio => Icons.bolt,
  IncidentType.actividadSospechosa => Icons.question_mark,
  IncidentType.otro => Icons.more_horiz,
};

/// Etiqueta corta para los chips de filtro.
String typeShortLabel(IncidentType type) => switch (type) {
  IncidentType.robo => 'Robo',
  IncidentType.agresionMujer => 'Agresión',
  IncidentType.maltratoAnimal => 'Animales',
  IncidentType.peleaColegio => 'Pelea',
  IncidentType.actividadSospechosa => 'Sospechosa',
  IncidentType.otro => 'Otro',
};

/// Etiqueta de cada tipo en el formulario de reporte (frame 06 de Figma).
String reportLabel(IncidentType type) => switch (type) {
  IncidentType.robo => 'Robo / asalto',
  IncidentType.agresionMujer => 'Agresión a mujer',
  IncidentType.maltratoAnimal => 'Maltrato animal',
  IncidentType.peleaColegio => 'Pelea / riña',
  IncidentType.actividadSospechosa => 'Actividad sospechosa',
  IncidentType.otro => 'Otro',
};

Color statusColor(IncidentStatus status) => switch (status) {
  IncidentStatus.verificado => const Color(0xFF2E7D32),
  IncidentStatus.sinVerificar => const Color(0xFFB26A00),
  IncidentStatus.descartado => const Color(0xFF6B7280),
};

/// "Hace 12 min", "Hace 5 h", "Hace 3 d".
String relativeTime(DateTime time, DateTime now) {
  final diff = now.difference(time);
  if (diff < const Duration(minutes: 1)) return 'Hace un momento';
  if (diff < const Duration(hours: 1)) return 'Hace ${diff.inMinutes} min';
  if (diff < const Duration(days: 1)) return 'Hace ${diff.inHours} h';
  return 'Hace ${diff.inDays} d';
}

/// "300 m" (redondeado a 10 m) o "1,2 km".
String formatDistance(double meters) {
  if (meters < 995) {
    final rounded = (meters / 10).round() * 10;
    return '${rounded < 10 ? 10 : rounded} m';
  }
  final km = meters / 1000;
  if (km >= 10) return '${km.round()} km';
  return '${km.toStringAsFixed(1).replaceAll('.', ',')} km';
}

/// "A 120 m de ti", "A 1,5 km de ti", o "En tu ubicación" si está encima.
String describeDistanceToUser(double meters) =>
    meters < 5 ? 'En tu ubicación' : 'A ${formatDistance(meters)} de ti';

/// "a 440 m de ti" / "en tu ubicación", para unir a la hora: "Hace 5 h · a 440 m de ti".
String distanceFromUser(double meters) =>
    meters < 5 ? 'en tu ubicación' : 'a ${formatDistance(meters)} de ti';
