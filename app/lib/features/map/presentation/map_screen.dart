import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/geo/arequipa.dart';
import '../../../core/location/location_service.dart';
import 'map_providers.dart';

const _zoomInicial = 16.0;

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key, this.mapController});

  /// Solo para tests: permite inspeccionar la cámara del mapa.
  final MapController? mapController;

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen>
    with WidgetsBindingObserver {
  late final MapController _controller =
      widget.mapController ?? MapController();

  bool _mapReady = false;
  bool _centeredOnUser = false;
  LatLng? _pendingTarget;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (widget.mapController == null) _controller.dispose();
    super.dispose();
  }

  /// Al volver de los ajustes del sistema, reintenta si faltaba la ubicación.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final location = ref.read(userLocationProvider).value;
    if (state == AppLifecycleState.resumed && location is LocationUnavailable) {
      ref.invalidate(userLocationProvider);
    }
  }

  /// Mueve la cámara; si el mapa aún no está listo, lo hace cuando lo esté.
  void _goTo(LatLng target) {
    if (_mapReady) {
      _controller.move(target, _zoomInicial);
    } else {
      _pendingTarget = target;
    }
  }

  void _onMapReady() {
    _mapReady = true;
    final target = _pendingTarget;
    if (target != null) {
      _pendingTarget = null;
      _controller.move(target, _zoomInicial);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Solo la primera posición centra el mapa; después el usuario manda
    ref.listen(userLocationProvider, (_, next) {
      final state = next.value;
      if (state is LocationFound && !_centeredOnUser) {
        _centeredOnUser = true;
        _goTo(state.position);
      }
    });

    final location = ref.watch(userLocationProvider);
    final state = location.value;

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _controller,
            options: MapOptions(
              initialCenter: ucspCenter,
              initialZoom: _zoomInicial,
              minZoom: 10,
              maxZoom: 19,
              onMapReady: _onMapReady,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'pe.civicsecurity.civic_security',
                tileProvider: ref.watch(tileProviderProvider),
              ),
              if (state is LocationFound)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: state.position,
                      width: 22,
                      height: 22,
                      child: const _UserDot(),
                    ),
                  ],
                ),
              const SimpleAttributionWidget(
                source: Text('OpenStreetMap contributors'),
              ),
            ],
          ),
          // Pin fijo al centro: marca dónde se ubicará el reporte (Tarea 9)
          const IgnorePointer(child: Center(child: _CenterPin())),
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: _statusBanner(location),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        key: const Key('boton-mi-ubicacion'),
        tooltip: 'Mi ubicación',
        onPressed: () {
          if (state is LocationFound) {
            _controller.move(state.position, _zoomInicial);
          } else {
            ref.invalidate(userLocationProvider);
          }
        },
        child: const Icon(Icons.my_location),
      ),
    );
  }

  Widget _statusBanner(AsyncValue<LocationState> location) {
    if (location.isLoading) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Text('Buscando tu ubicación…'),
        ),
      );
    }
    final state = location.value;
    if (state is! LocationUnavailable) return const SizedBox.shrink();

    final needsSettings =
        state.reason == LocationFailure.serviceDisabled ||
        state.reason == LocationFailure.deniedForever;

    return Card(
      key: const Key('aviso-ubicacion'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            Expanded(child: Text(_messageFor(state.reason))),
            TextButton(
              onPressed: () => needsSettings
                  ? ref
                        .read(locationServiceProvider)
                        .openSettingsFor(state.reason)
                  : ref.invalidate(userLocationProvider),
              child: Text(needsSettings ? 'Ajustes' : 'Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  String _messageFor(LocationFailure reason) => switch (reason) {
    LocationFailure.serviceDisabled =>
      'Activa la ubicación del teléfono para ver reportes cerca de ti. '
          'Mostrando la UCSP.',
    LocationFailure.denied =>
      'Necesitamos tu ubicación para mostrarte reportes cercanos. '
          'Mostrando la UCSP.',
    LocationFailure.deniedForever =>
      'El permiso de ubicación está bloqueado. Actívalo en los ajustes de la '
          'app. Mostrando la UCSP.',
    LocationFailure.unavailable =>
      'No pudimos obtener tu ubicación. Mostrando la UCSP.',
    LocationFailure.outsideArea =>
      'Estás fuera de Arequipa; Civic Security solo opera aquí. '
          'Mostrando la UCSP.',
  };
}

class _UserDot extends StatelessWidget {
  const _UserDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('mi-ubicacion'),
      decoration: BoxDecoration(
        color: Colors.blue,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black38)],
      ),
    );
  }
}

class _CenterPin extends StatelessWidget {
  const _CenterPin();

  @override
  Widget build(BuildContext context) {
    // La punta del pin queda exactamente en el centro del mapa
    return Transform.translate(
      offset: const Offset(0, -22),
      child: const Icon(
        Icons.location_pin,
        key: Key('pin-central'),
        size: 44,
        color: Colors.red,
      ),
    );
  }
}
