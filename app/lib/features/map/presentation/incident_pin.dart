import 'package:flutter/material.dart';

import '../../incident/domain/incident.dart';
import 'incident_style.dart';

/// Pin de un incidente en el mapa: círculo del color del tipo, con su ícono.
class IncidentPin extends StatelessWidget {
  const IncidentPin({super.key, required this.incident, required this.onTap});

  final Incident incident;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = typeColor(incident.tipo);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Opacity(
        // Un reporte descartado por la comunidad se ve apagado
        opacity: incident.estado == IncidentStatus.descartado ? 0.45 : 1,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: const [
                  BoxShadow(blurRadius: 4, color: Colors.black38),
                ],
              ),
              child: Icon(
                typeIcon(incident.tipo),
                size: 17,
                color: Colors.white,
              ),
            ),
            if (incident.estado == IncidentStatus.verificado)
              const Positioned(
                right: 2,
                bottom: 2,
                child: CircleAvatar(
                  radius: 7,
                  backgroundColor: Colors.white,
                  child: Icon(
                    Icons.check_circle,
                    size: 13,
                    color: Color(0xFF2E7D32),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
