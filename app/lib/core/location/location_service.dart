import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../geo/arequipa.dart';

/// Por qué no tenemos la ubicación del usuario.
enum LocationFailure {
  serviceDisabled,
  denied,
  deniedForever,
  unavailable,
  outsideArea,
}

sealed class LocationState {
  const LocationState();
}

final class LocationFound extends LocationState {
  const LocationFound(this.position);
  final LatLng position;
}

final class LocationUnavailable extends LocationState {
  const LocationUnavailable(this.reason);
  final LocationFailure reason;
}

/// Acceso a la ubicación del dispositivo. Es una interfaz para poder
/// reemplazarla por un falso en los tests.
abstract interface class LocationService {
  /// Pide permiso si hace falta y devuelve la primera posición.
  Future<LocationState> locate();

  /// Posiciones siguientes cuando el usuario se mueve.
  Stream<LatLng> watch();

  /// Abre los ajustes del sistema que permiten resolver [reason].
  Future<void> openSettingsFor(LocationFailure reason);
}

class GeolocatorLocationService implements LocationService {
  @override
  Future<LocationState> locate() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return const LocationUnavailable(LocationFailure.serviceDisabled);
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    switch (permission) {
      case LocationPermission.denied:
        return const LocationUnavailable(LocationFailure.denied);
      case LocationPermission.deniedForever:
        return const LocationUnavailable(LocationFailure.deniedForever);
      case LocationPermission.unableToDetermine:
        return const LocationUnavailable(LocationFailure.unavailable);
      case LocationPermission.whileInUse:
      case LocationPermission.always:
        break;
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      return LocationFound(LatLng(position.latitude, position.longitude));
    } on Exception {
      // Tiempo agotado o error del proveedor de ubicación
      return const LocationUnavailable(LocationFailure.unavailable);
    }
  }

  @override
  Stream<LatLng> watch() => Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.high,
      // Solo avisa si el usuario se movió al menos 20 m: ahorra batería
      distanceFilter: 20,
    ),
  ).map((p) => LatLng(p.latitude, p.longitude));

  @override
  Future<void> openSettingsFor(LocationFailure reason) async {
    if (reason == LocationFailure.serviceDisabled) {
      await Geolocator.openLocationSettings();
    } else {
      await Geolocator.openAppSettings();
    }
  }
}

final locationServiceProvider = Provider<LocationService>(
  (ref) => GeolocatorLocationService(),
);

/// Ubicación del usuario: primero la posición inicial y luego sus movimientos.
/// Una posición fuera de Arequipa se reporta como [LocationFailure.outsideArea].
final userLocationProvider = StreamProvider.autoDispose<LocationState>((
  ref,
) async* {
  final service = ref.watch(locationServiceProvider);

  final first = await service.locate();
  yield _checkArea(first);

  // Si hay posición, seguimos al usuario aunque hoy esté fuera de Arequipa
  if (first is LocationFound) {
    yield* service.watch().map((p) => _checkArea(LocationFound(p)));
  }
});

LocationState _checkArea(LocationState state) {
  if (state is LocationFound && !arequipaBounds.contains(state.position)) {
    return const LocationUnavailable(LocationFailure.outsideArea);
  }
  return state;
}
