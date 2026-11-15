import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../incident/domain/incident.dart';
import '../../map/presentation/map_providers.dart';
import '../domain/heat_map.dart';
import 'heat_controller.dart';
import 'heat_style.dart';

const _ink = Color(0xFF111827);
const _blue = Color(0xFF0A84FF);
const _red = Color(0xFFB91C1C);

// Tras mover o acercar el mapa se espera un momento antes de pedir los datos,
// para no hacer una petición por cada cuadro del gesto.
const _esperaAntesDeCargar = Duration(milliseconds: 400);

// Una celda se toca si el punto cae dentro de su círculo exterior
const _metrosPorGrado = 111320.0;

/// Frame 05b: la densidad de reportes por zona. Devuelve el centro de la zona
/// elegida con "Ver incidentes", o `null` si se vuelve con "Mapa".
class HeatMapScreen extends ConsumerStatefulWidget {
  const HeatMapScreen({
    super.key,
    required this.initialCenter,
    this.initialZoom = 14,
  });

  final LatLng initialCenter;
  final double initialZoom;

  @override
  ConsumerState<HeatMapScreen> createState() => _HeatMapScreenState();
}

class _HeatMapScreenState extends ConsumerState<HeatMapScreen> {
  final _controller = MapController();
  Timer? _loadTimer;
  bool _mapReady = false;
  HeatCell? _selected;

  @override
  void dispose() {
    _loadTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onMapReady() {
    _mapReady = true;
    _load();
  }

  void _scheduleLoad() {
    _loadTimer?.cancel();
    _loadTimer = Timer(_esperaAntesDeCargar, _load);
  }

  void _load() {
    final b = _controller.camera.visibleBounds;
    ref
        .read(heatControllerProvider.notifier)
        .load(
          Bbox.fromCorners(
            south: b.south,
            west: b.west,
            north: b.north,
            east: b.east,
          ),
        );
  }

  Future<void> _setWindow(HeatWindow window) async {
    setState(() => _selected = null);
    await ref.read(heatControllerProvider.notifier).setWindow(window);
  }

  /// La celda tocada, si el punto cae dentro de alguna; la más cercana si son
  /// varias (los círculos se pueden superponer).
  HeatCell? _cellAt(LatLng point, HeatMap data) {
    final radio = data.cellDeg * _metrosPorGrado * heatOuterFactor;
    const distance = Distance();
    HeatCell? mejor;
    var mejorDistancia = double.infinity;
    for (final cell in data.cells) {
      final d = distance.as(LengthUnit.Meter, point, cell.position);
      if (d <= radio && d < mejorDistancia) {
        mejor = cell;
        mejorDistancia = d;
      }
    }
    return mejor;
  }

  void _zoom(double delta) {
    final camera = _controller.camera;
    _controller.move(camera.center, (camera.zoom + delta).clamp(10.0, 19.0));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(heatControllerProvider);
    final data = state.data;

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
              onMapReady: _onMapReady,
              onPositionChanged: (_, _) {
                if (_mapReady) _scheduleLoad();
              },
              // Se lee el estado al tocar y no el de este build: flutter_map
              // conserva las opciones con las que se creó
              onTap: (_, point) {
                final actual = ref.read(heatControllerProvider).data;
                setState(
                  () => _selected = actual == null
                      ? null
                      : _cellAt(point, actual),
                );
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'pe.civicsecurity.civic_security',
                tileProvider: ref.watch(tileProviderProvider),
              ),
              if (data != null)
                CircleLayer(circles: heatCircles(data, selected: _selected)),
              const SimpleAttributionWidget(
                source: Text('OpenStreetMap contributors'),
              ),
            ],
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _TopBar(
                    selected: state.window,
                    onWindow: _setWindow,
                    onBack: () => Navigator.of(context).pop(),
                  ),
                  if (state.loading)
                    const Padding(
                      padding: EdgeInsets.only(top: 10),
                      child: SizedBox(
                        width: 160,
                        child: LinearProgressIndicator(minHeight: 3),
                      ),
                    ),
                  if (state.failure != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: _Notice(
                        key: const Key('aviso-calor-error'),
                        text: 'No pudimos cargar el mapa de calor.',
                        actionKey: const Key('reintentar-calor'),
                        onAction: () =>
                            ref.read(heatControllerProvider.notifier).retry(),
                      ),
                    )
                  else if (data != null && data.cells.isEmpty && !state.loading)
                    const Padding(
                      padding: EdgeInsets.only(top: 10),
                      child: _Notice(
                        key: Key('aviso-sin-reportes'),
                        text: 'Sin reportes en esta zona y período.',
                      ),
                    ),
                ],
              ),
            ),
          ),
          const Positioned(
            left: 16,
            bottom: 24,
            child: SafeArea(child: _Legend()),
          ),
          Positioned(
            right: 16,
            bottom: 24,
            child: SafeArea(
              child: _ZoomControls(
                onZoomIn: () => _zoom(1),
                onZoomOut: () => _zoom(-1),
              ),
            ),
          ),
          if (_selected != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 150,
              child: SafeArea(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: _ZoneCard(
                    cell: _selected!,
                    window: state.window,
                    onSeeIncidents: () =>
                        Navigator.of(context).pop(_selected!.position),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.selected,
    required this.onWindow,
    required this.onBack,
  });

  final HeatWindow selected;
  final ValueChanged<HeatWindow> onWindow;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Material(
          color: Colors.white,
          elevation: 2,
          shape: const StadiumBorder(),
          child: InkWell(
            key: const Key('boton-volver-mapa'),
            customBorder: const StadiumBorder(),
            onTap: onBack,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.arrow_back, size: 18, color: _blue),
                  SizedBox(width: 6),
                  Text(
                    'Mapa',
                    style: TextStyle(color: _blue, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ),
        for (final window in HeatWindow.values)
          _WindowChip(
            window: window,
            selected: window == selected,
            onTap: () => onWindow(window),
          ),
      ],
    );
  }
}

class _WindowChip extends StatelessWidget {
  const _WindowChip({
    required this.window,
    required this.selected,
    required this.onTap,
  });

  final HeatWindow window;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? _ink : Colors.white,
      elevation: 2,
      shape: const StadiumBorder(),
      child: InkWell(
        key: Key('chip-ventana-${window.wire}'),
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Text(
            window.label,
            style: TextStyle(
              color: selected ? Colors.white : _ink,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({super.key, required this.text, this.actionKey, this.onAction});

  final String text;
  final Key? actionKey;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 2,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: Text(text)),
            if (onAction != null)
              TextButton(
                key: actionKey,
                onPressed: onAction,
                child: const Text('Reintentar'),
              ),
          ],
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const Key('leyenda-intensidad'),
      color: Colors.white,
      elevation: 2,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          width: 150,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Intensidad',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
              const SizedBox(height: 8),
              Container(
                height: 8,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  gradient: LinearGradient(
                    colors: [heatColor(0), heatColor(0.5), heatColor(1)],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Baja', style: TextStyle(fontSize: 11)),
                  Text('Alta', style: TextStyle(fontSize: 11)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ZoomControls extends StatelessWidget {
  const _ZoomControls({required this.onZoomIn, required this.onZoomOut});

  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 2,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: const Key('zoom-mas'),
            tooltip: 'Acercar',
            onPressed: onZoomIn,
            icon: const Icon(Icons.add),
          ),
          const Divider(height: 1),
          IconButton(
            key: const Key('zoom-menos'),
            tooltip: 'Alejar',
            onPressed: onZoomOut,
            icon: const Icon(Icons.remove),
          ),
        ],
      ),
    );
  }
}

/// El cuadro que sale al tocar una zona.
class _ZoneCard extends StatelessWidget {
  const _ZoneCard({
    required this.cell,
    required this.window,
    required this.onSeeIncidents,
  });

  final HeatCell cell;
  final HeatWindow window;
  final VoidCallback onSeeIncidents;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 380),
      child: Material(
        key: const Key('zona-actividad'),
        color: Colors.white,
        elevation: 6,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                zoneTitle(cell.count),
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                zoneSummary(cell, window),
                style: const TextStyle(color: Color(0xFF4B5563)),
              ),
              const SizedBox(height: 4),
              Text(
                'Más frecuente: ${cell.franjaLabel}',
                style: const TextStyle(
                  color: _red,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              TextButton(
                key: const Key('ver-incidentes'),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 36),
                ),
                onPressed: onSeeIncidents,
                child: const Text('Ver incidentes ›'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
