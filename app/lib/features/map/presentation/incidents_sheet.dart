import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../incident/domain/incident.dart';
import 'incident_style.dart';
import 'status_chip.dart';

/// Hoja inferior arrastrable: "N incidentes en esta zona" y su lista.
class IncidentsSheet extends StatelessWidget {
  const IncidentsSheet({
    super.key,
    required this.incidents,
    required this.loading,
    required this.onSelect,
    this.userPosition,
    this.initialExtent = 0.25,
  });

  final List<Incident> incidents;
  final bool loading;
  final ValueChanged<Incident> onSelect;
  final LatLng? userPosition;
  final double initialExtent;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().toUtc();

    return DraggableScrollableSheet(
      initialChildSize: initialExtent,
      minChildSize: 0.12,
      maxChildSize: 0.75,
      snap: true,
      builder: (context, scrollController) {
        return Material(
          elevation: 8,
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          clipBehavior: Clip.antiAlias,
          child: CustomScrollView(
            controller: scrollController,
            slivers: [
              SliverToBoxAdapter(child: _header(context)),
              if (incidents.isEmpty)
                const SliverToBoxAdapter(child: SizedBox(height: 24))
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  sliver: SliverList.separated(
                    itemCount: incidents.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) =>
                        _card(context, incidents[i], now),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _header(BuildContext context) {
    final n = incidents.length;
    final title = n == 0
        ? 'Sin reportes en esta zona'
        : '$n incidente${n == 1 ? '' : 's'} en esta zona';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Text(
                'Últimas 24 h',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          if (loading) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(minHeight: 2),
          ],
        ],
      ),
    );
  }

  Widget _card(BuildContext context, Incident incident, DateTime now) {
    final color = typeColor(incident.tipo);
    final distance = userPosition == null
        ? null
        : const Distance().as(
            LengthUnit.Meter,
            userPosition!,
            incident.position,
          );
    final when = relativeTime(incident.creadoEn, now);

    return Card(
      key: Key('tarjeta-${incident.id}'),
      margin: EdgeInsets.zero,
      elevation: 0,
      color: const Color(0xFFF9FAFB),
      child: ListTile(
        onTap: () => onSelect(incident),
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          child: Icon(typeIcon(incident.tipo), color: color),
        ),
        title: Text(
          incident.tipo.label,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                distance == null
                    ? when
                    : '$when · a ${formatDistance(distance)} de ti',
              ),
              const SizedBox(height: 4),
              StatusChip(incident.estado),
            ],
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}
