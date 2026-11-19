import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../incident/domain/incident.dart';
import 'incident_photo.dart';
import 'incident_style.dart';
import 'map_incidents_controller.dart';
import 'status_chip.dart';
import 'vote_section.dart';

/// Detalle de un incidente: qué pasó, cuándo y a qué distancia, su foto y la
/// validación comunitaria ("Lo confirmo" / "Es falso").
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

class _IncidentDetail extends ConsumerWidget {
  const _IncidentDetail({required this.incident, this.userPosition});

  final Incident incident;
  final LatLng? userPosition;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // La versión más nueva del reporte: si otra persona vota mientras esta hoja
    // está abierta, los conteos y el estado cambian al instante
    final incident =
        ref.watch(
          mapIncidentsProvider.select(
            (s) =>
                s.incidents.where((i) => i.id == this.incident.id).firstOrNull,
          ),
        ) ??
        this.incident;
    final color = typeColor(incident.tipo);
    final distance = userPosition == null
        ? null
        : const Distance().as(
            LengthUnit.Meter,
            userPosition!,
            incident.position,
          );
    final when = relativeTime(incident.creadoEn, DateTime.now().toUtc());

    // Con foto el detalle puede no caber en una pantalla chica: se desplaza
    return SingleChildScrollView(
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
            distance == null ? when : '$when · ${distanceFromUser(distance)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Text(incident.descripcion ?? 'Sin descripción'),
          if (incident.tieneFoto) ...[
            const SizedBox(height: 14),
            IncidentPhoto(incidentId: incident.id),
          ],
          VoteSection(incident: incident, userPosition: userPosition),
        ],
      ),
    );
  }
}
