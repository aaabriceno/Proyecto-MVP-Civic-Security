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
  const LocationFound(this.position, {this.accuracyMeters});
  final LatLng position;

  /// Radio de error estimado, en metros: el usuario está dentro de ese círculo
  /// alrededor de [position]. `null` si el sistema no lo informó. Un GPS bueno da
  /// decenas de metros; la ubicación por Wi-Fi puede dar cientos.
  final double? accuracyMeters;
}

/// Convierte la precisión que informa el sistema en un valor usable.
///
/// Android informa 0 cuando no sabe cuál es la precisión, y un valor negativo,
/// NaN o infinito no describe un radio: en todos esos casos es mejor no mostrar
/// nada que dibujar un círculo inventado.
double? accuracyFrom(double raw) => raw.isFinite && raw > 0 ? raw : null;

final class LocationUnavailable extends LocationState {
  const LocationUnavailable(this.reason);
  final LocationFailure reason;
}

/// Acceso a la ubicación del dispositivo. Es una interfaz para poder
/// reemplazarla por un falso en los tests.
abstract interface class LocationService {
  /// Pide permiso si hace falta y devuelve la primera posición.
  Future<LocationState> locate();

  /// Posiciones siguientes cuando el usuario se mueve o mejora la precisión.
  Stream<LocationFound> watch();

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
      return _found(position);
    } on Exception {
      // Tiempo agotado o error del proveedor de ubicación
      return const LocationUnavailable(LocationFailure.unavailable);
    }
  }

  @override
  Stream<LocationFound> watch() => Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.high,
      // Solo avisa si el usuario se movió al menos 20 m: ahorra batería
      distanceFilter: 20,
    ),
  ).map(_found);

  LocationFound _found(Position p) => LocationFound(
    LatLng(p.latitude, p.longitude),
    accuracyMeters: accuracyFrom(p.accuracy),
  );

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
    yield* service.watch().map(_checkArea);
  }
});

LocationState _checkArea(LocationState state) {
  if (state is LocationFound && !arequipaBounds.contains(state.position)) {
    return const LocationUnavailable(LocationFailure.outsideArea);
  }
  return state;
}
