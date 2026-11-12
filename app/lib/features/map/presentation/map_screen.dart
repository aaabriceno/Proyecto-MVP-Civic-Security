import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/geo/arequipa.dart';
import '../../../core/location/location_service.dart';
import '../../auth/domain/auth_models.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../incident/domain/incident.dart';
import '../../report/presentation/adjust_location_screen.dart';
import '../../report/presentation/report_screen.dart';
import 'incident_detail.dart';
import 'incident_pin.dart';
import 'incidents_sheet.dart';
import 'live_map_controller.dart';
import 'live_status_chip.dart';
import 'map_incidents_controller.dart';
import 'map_providers.dart';
import 'type_filter_bar.dart';

const _zoomInicial = 16.0;
const _extentInicialHoja = 0.25;

/// Tiempo que el mapa espera sin moverse antes de pedir los incidentes del
/// área visible (evita una consulta por cada fotograma al arrastrar).
const _esperaAntesDeCargar = Duration(milliseconds: 500);

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({
    super.key,
    this.mapController,
    this.readOnly = false,
    this.onSignIn,
  });

  /// Solo para tests: permite inspeccionar la cámara del mapa.
  final MapController? mapController;

  /// Mapa para quien aún no tiene cuenta: se ve todo, pero no se puede
  /// reportar. En vez de "Reportar" ofrece iniciar sesión.
  final bool readOnly;

  /// Qué hacer cuando, en modo [readOnly], la persona quiere iniciar sesión.
  final VoidCallback? onSignIn;

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
  Timer? _loadTimer;

  // Para que el botón de ubicación suba junto con la hoja inferior
  final _sheetExtent = ValueNotifier<double>(_extentInicialHoja);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Empieza a escuchar reportes nuevos. Si la conexión se cae, el canal
    // reintenta solo mientras la pantalla esté abierta.
    ref.read(liveMapProvider.notifier).start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _loadTimer?.cancel();
    _sheetExtent.dispose();
    if (widget.mapController == null) _controller.dispose();
    super.dispose();
  }

  /// - En segundo plano (`paused`) corta el tiempo real: Android igual mata
  ///   el socket y mantenerlo gasta batería. Al volver (`resumed`) reconecta, y
  ///   al quedar conectado se recarga el snapshot (ver [LiveMapController]).
  ///   `inactive` NO corta: ocurre al mostrar el diálogo de permisos.
  /// - Al volver de los ajustes del sistema, reintenta si faltaba la ubicación.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final live = ref.read(liveMapProvider.notifier);
    switch (state) {
      case AppLifecycleState.paused:
        live.stop();
      case AppLifecycleState.resumed:
        live.start();
        final location = ref.read(userLocationProvider).value;
        if (location is LocationUnavailable) {
          ref.invalidate(userLocationProvider);
        }
      case AppLifecycleState.inactive ||
          AppLifecycleState.hidden ||
          AppLifecycleState.detached:
        break;
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
    _scheduleLoad();
  }

  void _scheduleLoad() {
    _loadTimer?.cancel();
    _loadTimer = Timer(_esperaAntesDeCargar, _loadVisibleArea);
  }

  void _loadVisibleArea() {
    if (!mounted || !_mapReady) return;
    final b = _controller.camera.visibleBounds;
    ref
        .read(mapIncidentsProvider.notifier)
        .load(
          Bbox.fromCorners(
            south: b.south,
            west: b.west,
            north: b.north,
            east: b.east,
          ),
        );
  }

  /// Frame 05 -> 06: con ubicación abre el formulario; sin ella, primero pide
  /// elegir el lugar en el mapa (frame 06c).
  Future<void> _startReport(LatLng? userPosition) async {
    var location = userPosition;
    if (location == null) {
      final camera = _controller.camera;
      location = await Navigator.of(context).push<LatLng>(
        MaterialPageRoute(
          builder: (_) => AdjustLocationScreen(
            initialCenter: camera.center,
            // Si el mapa muestra toda la ciudad, acerca para poder ubicar
            initialZoom: camera.zoom < 15 ? 15 : camera.zoom,
          ),
        ),
      );
      if (location == null || !mounted) return;
    }

    final incident = await Navigator.of(context).push<Incident>(
      MaterialPageRoute(
        builder: (_) => ReportScreen(
          initialLocation: location!,
          isUserLocation: userPosition != null,
          userPosition: userPosition,
        ),
      ),
    );
    if (incident != null && mounted) _controller.move(incident.position, 17);
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
    final locationState = location.value;
    final userPosition = locationState is LocationFound
        ? locationState.position
        : null;

    final data = ref.watch(mapIncidentsProvider);
    final incidents = ref.watch(visibleIncidentsProvider);
    final filter = ref.watch(typeFilterProvider);
    final live = ref.watch(liveMapProvider);
    final auth = ref.watch(authControllerProvider);
    final hasAccount =
        !widget.readOnly &&
        (auth.status == AuthStatus.signedIn ||
            auth.status == AuthStatus.offline);

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _controller,
            options: MapOptions(
              // Sin ubicación del usuario se ve Arequipa completa
              initialCameraFit: CameraFit.bounds(
                bounds: arequipaBounds,
                padding: const EdgeInsets.all(16),
              ),
              minZoom: 10,
              maxZoom: 19,
              onMapReady: _onMapReady,
              onPositionChanged: (_, _) {
                if (_mapReady) _scheduleLoad();
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'pe.civicsecurity.civic_security',
                tileProvider: ref.watch(tileProviderProvider),
              ),
              if (userPosition != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: userPosition,
                      width: 22,
                      height: 22,
                      child: const _UserDot(),
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  for (final incident in incidents)
                    Marker(
                      point: incident.position,
                      width: 44,
                      height: 44,
                      child: IncidentPin(
                        key: Key('pin-${incident.id}'),
                        incident: incident,
                        onTap: () => showIncidentDetail(
                          context,
                          incident,
                          userPosition: userPosition,
                        ),
                      ),
                    ),
                ],
              ),
              const SimpleAttributionWidget(
                source: Text('OpenStreetMap contributors'),
              ),
            ],
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TypeFilterBar(
                    selected: filter,
                    onSelected: ref.read(typeFilterProvider.notifier).select,
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: LiveStatusChip(status: live),
                    ),
                  ),
                  if (auth.status == AuthStatus.offline && !widget.readOnly)
                    const _Banner(
                      key: Key('aviso-sesion-sin-confirmar'),
                      message:
                          'Sin conexión: no pudimos confirmar tu sesión. '
                          'Lo reintentaremos solos.',
                    ),
                  _locationBanner(location),
                  _dataBanner(data),
                ],
              ),
            ),
          ),
          NotificationListener<DraggableScrollableNotification>(
            onNotification: (n) {
              _sheetExtent.value = n.extent;
              return false;
            },
            child: IncidentsSheet(
              incidents: incidents,
              loading: data.loading,
              userPosition: userPosition,
              initialExtent: _extentInicialHoja,
              onSelect: (incident) => showIncidentDetail(
                context,
                incident,
                userPosition: userPosition,
              ),
            ),
          ),
          ValueListenableBuilder<double>(
            valueListenable: _sheetExtent,
            builder: (context, extent, _) {
              final height = MediaQuery.sizeOf(context).height;
              return Positioned(
                right: 16,
                // Sube con la hoja, pero se queda en pantalla si se expande
                bottom: height * extent.clamp(0.0, 0.5) + 16,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (hasAccount) ...[
                      FloatingActionButton.small(
                        key: const Key('boton-cuenta'),
                        heroTag: null,
                        tooltip: 'Mi cuenta',
                        onPressed: () => _openAccount(auth.user),
                        child: const Icon(Icons.person_outline),
                      ),
                      const SizedBox(height: 12),
                    ],
                    FloatingActionButton.small(
                      key: const Key('boton-mi-ubicacion'),
                      // Sin animación Hero: dos botones con la misma etiqueta
                      // hacen fallar el cambio de pantalla
                      heroTag: null,
                      tooltip: 'Mi ubicación',
                      onPressed: () {
                        if (userPosition != null) {
                          _controller.move(userPosition, _zoomInicial);
                        } else {
                          ref.invalidate(userLocationProvider);
                        }
                      },
                      child: const Icon(Icons.my_location),
                    ),
                    const SizedBox(height: 12),
                    if (widget.readOnly)
                      if (widget.onSignIn != null)
                        FloatingActionButton.extended(
                          key: const Key('boton-iniciar-sesion-mapa'),
                          heroTag: null,
                          onPressed: widget.onSignIn,
                          icon: const Icon(Icons.login),
                          label: const Text('Iniciar sesión para reportar'),
                        )
                      else
                        const SizedBox.shrink()
                    else
                      FloatingActionButton.extended(
                        key: const Key('boton-reportar'),
                        heroTag: null,
                        backgroundColor: const Color(0xFFDC2626),
                        foregroundColor: Colors.white,
                        onPressed: () => _startReport(userPosition),
                        icon: const Icon(Icons.add),
                        label: const Text('Reportar'),
                      ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  /// Hoja provisional con la cuenta y "Cerrar sesión". El diseño final es el
  /// frame 10 (Perfil), que llegará con la barra de pestañas.
  void _openAccount(AuthUser? user) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                user?.alias ?? 'Sesión guardada',
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(switch (user?.nivel) {
                AuthLevel.verificado => 'Cuenta verificada',
                AuthLevel.invitado => 'Cuenta sin verificar',
                null => 'No pudimos confirmarla: sin conexión',
              }),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  key: const Key('boton-cerrar-sesion'),
                  onPressed: () {
                    Navigator.of(sheetContext).pop();
                    ref.read(authControllerProvider.notifier).logout();
                  },
                  icon: const Icon(Icons.logout),
                  label: const Text('Cerrar sesión'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _locationBanner(AsyncValue<LocationState> location) {
    if (location.isLoading) {
      return const _Banner(
        key: Key('buscando-ubicacion'),
        message: 'Buscando tu ubicación…',
      );
    }
    final state = location.value;
    if (state is! LocationUnavailable) return const SizedBox.shrink();

    final needsSettings =
        state.reason == LocationFailure.serviceDisabled ||
        state.reason == LocationFailure.deniedForever;

    return _Banner(
      key: const Key('aviso-ubicacion'),
      message: _messageFor(state.reason),
      actionLabel: needsSettings ? 'Ajustes' : 'Reintentar',
      onAction: () => needsSettings
          ? ref.read(locationServiceProvider).openSettingsFor(state.reason)
          : ref.invalidate(userLocationProvider),
    );
  }

  Widget _dataBanner(MapIncidentsState data) {
    final failure = data.failure;
    if (failure == null) return const SizedBox.shrink();

    return _Banner(
      key: const Key('aviso-datos'),
      message: failure.message,
      actionKey: const Key('reintentar-datos'),
      actionLabel: 'Reintentar',
      onAction: () => ref.read(mapIncidentsProvider.notifier).retry(),
    );
  }

  String _messageFor(LocationFailure reason) => switch (reason) {
    LocationFailure.serviceDisabled =>
      'Activa la ubicación del teléfono para ver reportes cerca de ti.',
    LocationFailure.denied =>
      'Necesitamos tu ubicación para mostrarte reportes cercanos.',
    LocationFailure.deniedForever =>
      'El permiso de ubicación está bloqueado. Actívalo en los ajustes de la '
          'app.',
    LocationFailure.unavailable => 'No pudimos obtener tu ubicación.',
    LocationFailure.outsideArea =>
      'Estás fuera de Arequipa; por ahora Civic Security solo opera aquí.',
  };
}

class _Banner extends StatelessWidget {
  const _Banner({
    super.key,
    required this.message,
    this.actionLabel,
    this.actionKey,
    this.onAction,
  });

  final String message;
  final String? actionLabel;
  final Key? actionKey;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(
          children: [
            Expanded(child: Text(message)),
            if (actionLabel != null)
              TextButton(
                key: actionKey,
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
          ],
        ),
      ),
    );
  }
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
