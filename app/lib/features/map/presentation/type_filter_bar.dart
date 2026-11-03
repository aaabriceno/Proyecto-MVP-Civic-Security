import 'package:flutter/material.dart';

import '../../incident/domain/incident.dart';
import 'incident_style.dart';

/// Chips "Todos · Robo · Agresión…" para filtrar el mapa por tipo.
class TypeFilterBar extends StatelessWidget {
  const TypeFilterBar({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final IncidentType? selected;
  final ValueChanged<IncidentType?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _chip(
            key: const Key('filtro-todos'),
            label: 'Todos',
            selected: selected == null,
            onTap: () => onSelected(null),
          ),
          for (final type in IncidentType.values)
            _chip(
              key: Key('filtro-${type.wire}'),
              label: typeShortLabel(type),
              dot: typeColor(type),
              selected: selected == type,
              onTap: () => onSelected(type),
            ),
        ],
      ),
    );
  }

  Widget _chip({
    required Key key,
    required String label,
    required bool selected,
    required VoidCallback onTap,
    Color? dot,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        key: key,
        selected: selected,
        onSelected: (_) => onTap(),
        showCheckmark: false,
        avatar: dot == null
            ? null
            : Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
              ),
        label: Text(label),
        backgroundColor: Colors.white,
        selectedColor: const Color(0xFF111827),
        labelStyle: TextStyle(color: selected ? Colors.white : Colors.black87),
        side: BorderSide.none,
        elevation: 1,
      ),
    );
  }
}
