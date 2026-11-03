import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../incident/domain/incident.dart';
import 'incident_style.dart';
import 'status_chip.dart';

/// Resumen de un incidente. Es provisional: el detalle completo, con la
/// validación comunitaria ("Lo confirmo" / "Es falso"), llega después.
Future<void> showIncidentDetail(
  BuildContext context,
  Incident incident, {
  LatLng? userPosition,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) =>
        _IncidentDetail(incident: incident, userPosition: userPosition),
  );
}

class _IncidentDetail extends StatelessWidget {
  const _IncidentDetail({required this.incident, this.userPosition});

  final Incident incident;
  final LatLng? userPosition;

  @override
  Widget build(BuildContext context) {
    final color = typeColor(incident.tipo);
    final distance = userPosition == null
        ? null
        : const Distance().as(
            LengthUnit.Meter,
            userPosition!,
            incident.position,
          );
    final when = relativeTime(incident.creadoEn, DateTime.now().toUtc());

    return Padding(
      key: const Key('detalle-incidente'),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: color.withValues(alpha: 0.15),
                child: Icon(typeIcon(incident.tipo), color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  incident.tipo.label,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              StatusChip(incident.estado),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            distance == null
                ? when
                : '$when · a ${formatDistance(distance)} de ti',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Text(incident.descripcion ?? 'Sin descripción'),
        ],
      ),
    );
  }
}
