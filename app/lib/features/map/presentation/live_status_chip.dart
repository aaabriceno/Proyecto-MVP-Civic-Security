import 'package:flutter/material.dart';

import '../../../core/realtime/phoenix_channel.dart';

/// Pastilla "En vivo" / "Conectando…" sobre el mapa. Avisa si los reportes
/// nuevos están llegando solos o si hay que esperar a que la conexión vuelva.
class LiveStatusChip extends StatelessWidget {
  const LiveStatusChip({super.key, required this.status});

  final RealtimeStatus status;

  @override
  Widget build(BuildContext context) {
    final live = status == RealtimeStatus.connected;
    final label = switch (status) {
      RealtimeStatus.connected => 'En vivo',
      RealtimeStatus.connecting => 'Conectando…',
      RealtimeStatus.disconnected => 'Reconectando…',
    };
    final color = live ? const Color(0xFF16A34A) : const Color(0xFFD97706);

    return Semantics(
      container: true,
      label: live
          ? 'Mapa en vivo: los reportes nuevos aparecen solos'
          : 'Sin conexión en vivo: $label',
      child: ExcludeSemantics(
        child: Material(
          key: const Key('estado-en-vivo'),
          color: Theme.of(context).colorScheme.surface,
          elevation: 2,
          shape: const StadiumBorder(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: Theme.of(
                    context,
                  ).textTheme.labelMedium?.copyWith(color: color),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
