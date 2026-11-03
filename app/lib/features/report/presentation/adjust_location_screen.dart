import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/geo/arequipa.dart';
import '../../map/presentation/incident_style.dart';
import '../../map/presentation/map_providers.dart';

const _blue = Color(0xFF0A84FF);
const _red = Color(0xFFDC2626);

/// Frame 06c: el usuario mueve el mapa hasta que el pin fijo queda sobre el
/// lugar exacto. Devuelve la ubicación elegida, o `null` si vuelve atrás.
class AdjustLocationScreen extends ConsumerStatefulWidget {
  const AdjustLocationScreen({
    super.key,
    required this.initialCenter,
    this.userPosition,
    this.initialZoom = 17,
  });

  final LatLng initialCenter;

  /// Dónde está el usuario; `null` si no se pudo obtener su ubicación.
  final LatLng? userPosition;
  final double initialZoom;

  @override
  ConsumerState<AdjustLocationScreen> createState() =>
      _AdjustLocationScreenState();
}

class _AdjustLocationScreenState extends ConsumerState<AdjustLocationScreen> {
  final _controller = MapController();
  late final ValueNotifier<LatLng> _center = ValueNotifier(
    widget.initialCenter,
  );

  @override
  void dispose() {
    _center.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _useMyLocation() {
    final user = widget.userPosition;
    if (user == null) return;
    _center.value = user;
    _controller.move(user, widget.initialZoom);
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.userPosition;

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _controller,
            options: MapOptions(
              initialCenter: widget.initialCenter,
              initialZoom: widget.initialZoom,
              minZoom: 10,
              maxZoom: 19,
              onPositionChanged: (camera, _) => _center.value = camera.center,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'pe.civicsecurity.civic_security',
                tileProvider: ref.watch(tileProviderProvider),
              ),
              if (user != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: user,
                      width: 56,
                      height: 44,
                      child: const _UserDot(),
                    ),
                  ],
                ),
              const SimpleAttributionWidget(
                source: Text('OpenStreetMap contributors'),
              ),
            ],
          ),
          // Pin fijo: su punta queda exactamente en el centro del mapa
          IgnorePointer(
            child: Center(
              child: FractionalTranslation(
                translation: const Offset(0, -0.5),
                child: ValueListenableBuilder<LatLng>(
                  valueListenable: _center,
                  builder: (context, center, _) => _CenterPin(
                    label: user == null
                        ? null
                        : describeDistanceToUser(
                            const Distance().as(LengthUnit.Meter, user, center),
                          ),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Align(
                alignment: Alignment.topCenter,
                child: _InstructionsCard(
                  onBack: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: ValueListenableBuilder<LatLng>(
              valueListenable: _center,
              builder: (context, center, _) => _BottomCard(
                center: center,
                canUseMyLocation: user != null,
                onUseMyLocation: _useMyLocation,
                onConfirm: () => Navigator.of(context).pop(center),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InstructionsCard extends StatelessWidget {
  const _InstructionsCard({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextButton.icon(
              key: const Key('volver'),
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('Volver'),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '¿Dónde ocurrió exactamente?',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Mueve el mapa hasta que el pin rojo quede sobre el lugar. '
                    'Pellizca para acercar.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomCard extends StatelessWidget {
  const _BottomCard({
    required this.center,
    required this.canUseMyLocation,
    required this.onUseMyLocation,
    required this.onConfirm,
  });

  final LatLng center;
  final bool canUseMyLocation;
  final VoidCallback onUseMyLocation;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final inArea = arequipaBounds.contains(center);

    return Material(
      elevation: 8,
      color: Colors.white,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Ubicación seleccionada',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 2),
              Text(
                formatCoordinates(center),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (!inArea) ...[
                const SizedBox(height: 8),
                const Text(
                  'Esta ubicación está fuera de Arequipa; por ahora Civic '
                  'Security solo opera aquí.',
                  style: TextStyle(color: _red),
                ),
              ],
              const SizedBox(height: 12),
              if (canUseMyLocation) ...[
                OutlinedButton.icon(
                  key: const Key('usar-mi-ubicacion'),
                  onPressed: onUseMyLocation,
                  icon: const Icon(Icons.my_location, size: 18),
                  label: const Text('Usar mi ubicación actual'),
                ),
                const SizedBox(height: 8),
              ],
              FilledButton(
                key: const Key('confirmar-ubicacion'),
                style: FilledButton.styleFrom(
                  backgroundColor: _blue,
                  minimumSize: const Size.fromHeight(52),
                ),
                onPressed: inArea ? onConfirm : null,
                child: const Text('Confirmar ubicación'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "-16.43000, -71.50500": se muestra en lugar de una dirección porque
/// convertir coordenadas en dirección exigiría enviarlas a un servicio externo.
String formatCoordinates(LatLng p) =>
    '${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)}';

class _CenterPin extends StatelessWidget {
  const _CenterPin({this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF111827),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              label!,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        const SizedBox(height: 6),
        Container(
          key: const Key('pin-central'),
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: _red,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black38)],
          ),
          child: const Icon(Icons.priority_high, color: Colors.white),
        ),
        Container(width: 3, height: 14, color: _red),
      ],
    );
  }
}

class _UserDot extends StatelessWidget {
  const _UserDot();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          key: const Key('mi-ubicacion'),
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: _blue,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black38)],
          ),
        ),
        const Text(
          'Tú',
          style: TextStyle(
            color: _blue,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
