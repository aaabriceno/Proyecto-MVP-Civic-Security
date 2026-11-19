import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/network/api_failure.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../incident/data/incident_repository.dart';
import '../../incident/domain/incident.dart';
import 'map_incidents_controller.dart';

/// Qué decirle a la persona cuando su voto no se pudo registrar. Solo mensajes
/// propios: nunca el texto del servidor.
String voteFailureMessage(ApiFailure failure) => switch (failure.code) {
  'network' => 'No pudimos enviar tu voto. Revisa tu conexión.',
  'not_verified' =>
    'Verifica tu cuenta con el DNI en tu perfil para confirmar o negar '
        'reportes.',
  'own_report' => 'No puedes votar tu propio reporte.',
  'too_far' =>
    'Tienes que estar cerca del lugar del reporte para votarlo. '
        'Revisa que tu ubicación sea la correcta.',
  'voting_closed' => 'Este reporte ya no recibe votos.',
  'unauthorized' || 'invalid_token' => 'Inicia sesión para votar.',
  _ => 'No pudimos registrar tu voto. Intenta de nuevo.',
};

/// "¿Es verídico este reporte?": cuántas personas lo confirman o lo niegan y,
/// mientras siga sin verificar, los botones para votar.
///
/// Solo votan cuentas verificadas, a menos de 1 km del lugar y una vez por
/// reporte; eso lo decide el servidor, aquí solo se explica el motivo si rechaza.
class VoteSection extends ConsumerStatefulWidget {
  const VoteSection({
    super.key,
    required this.incident,
    required this.userPosition,
  });

  final Incident incident;

  /// Dónde está la persona. Sin ella no se puede votar: el servidor exige estar
  /// cerca del lugar.
  final LatLng? userPosition;

  @override
  ConsumerState<VoteSection> createState() => _VoteSectionState();
}

class _VoteSectionState extends ConsumerState<VoteSection> {
  bool _sending = false;

  /// Lo que se le dice a la persona cuando ya no puede votar más aquí.
  String? _done;
  String? _error;

  Future<void> _vote(VoteValue value) async {
    if (_sending) return;

    final position = widget.userPosition;
    if (position == null) {
      setState(
        () => _error =
            'Activa tu ubicación para votar: tienes que estar cerca del '
            'lugar del reporte.',
      );
      return;
    }

    // Se toman antes de esperar: si la hoja se cierra mientras tanto, el voto
    // igual se refleja en el mapa
    final repository = ref.read(incidentRepositoryProvider);
    final map = ref.read(mapIncidentsProvider.notifier);
    setState(() {
      _sending = true;
      _error = null;
    });

    try {
      final updated = await repository.vote(
        widget.incident.id,
        value,
        position,
      );
      map.upsert(updated);
      if (!mounted) return;
      setState(() {
        _sending = false;
        _done = 'Gracias, tu voto quedó registrado.';
      });
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        if (failure.code == 'already_voted') {
          _done = 'Ya votaste en este reporte.';
        } else {
          _error = voteFailureMessage(failure);
        }
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = voteFailureMessage(const ApiFailure.unexpected());
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final incident = widget.incident;
    final theme = Theme.of(context);
    final signedIn = ref.watch(
      authControllerProvider.select(
        (s) =>
            s.status == AuthStatus.signedIn || s.status == AuthStatus.offline,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 28),
        Text('¿Es verídico este reporte?', style: theme.textTheme.titleSmall),
        const SizedBox(height: 10),
        // Wrap y no Row: en una pantalla angosta el segundo conteo baja de línea
        Wrap(
          spacing: 20,
          runSpacing: 8,
          children: [
            _Count(
              key: const Key('conteo-confirmaciones'),
              icon: Icons.thumb_up_alt_outlined,
              count: incident.confirmaciones,
              label: 'confirman',
            ),
            _Count(
              key: const Key('conteo-falsos'),
              icon: Icons.thumb_down_alt_outlined,
              count: incident.falsos,
              label: 'dicen que es falso',
            ),
          ],
        ),
        const SizedBox(height: 12),
        ..._action(theme, incident, signedIn),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(
            _error!,
            key: const Key('voto-error'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
      ],
    );
  }

  List<Widget> _action(ThemeData theme, Incident incident, bool signedIn) {
    // La comunidad ya decidió: no hay nada más que votar
    if (incident.estado == IncidentStatus.verificado) {
      return [const Text('La comunidad verificó este reporte.')];
    }
    if (incident.estado == IncidentStatus.descartado) {
      return [const Text('La comunidad descartó este reporte.')];
    }
    if (!signedIn) {
      return [
        const Text(
          'Inicia sesión y verifica tu cuenta con el DNI para confirmar o '
          'negar reportes.',
        ),
      ];
    }
    if (_done != null) {
      return [
        Row(
          key: const Key('voto-registrado'),
          children: [
            Icon(Icons.check_circle, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(child: Text(_done!)),
          ],
        ),
      ];
    }
    return [
      Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              key: const Key('votar-confirmo'),
              onPressed: _sending ? null : () => _vote(VoteValue.confirmo),
              icon: const Icon(Icons.thumb_up_alt_outlined),
              label: const Text('Lo confirmo'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton.icon(
              key: const Key('votar-falso'),
              onPressed: _sending ? null : () => _vote(VoteValue.falso),
              icon: const Icon(Icons.thumb_down_alt_outlined),
              label: const Text('Es falso'),
            ),
          ),
        ],
      ),
      if (_sending)
        const Padding(
          padding: EdgeInsets.only(top: 12),
          child: LinearProgressIndicator(key: Key('votando')),
        ),
    ];
  }
}

class _Count extends StatelessWidget {
  const _Count({
    super.key,
    required this.icon,
    required this.count,
    required this.label,
  });

  final IconData icon;
  final int count;
  final String label;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 6),
        Text('$count', style: style.titleSmall),
        const SizedBox(width: 4),
        Text(label, style: style.bodySmall),
      ],
    );
  }
}
