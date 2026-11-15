import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_failure.dart';
import '../../incident/domain/incident.dart';
import '../data/heat_repository.dart';
import '../domain/heat_map.dart';

class HeatState {
  const HeatState({
    this.window = HeatWindow.day,
    this.loading = false,
    this.data,
    this.failure,
  });

  final HeatWindow window;
  final bool loading;

  /// Lo último que se pudo cargar. Se conserva mientras se pide algo nuevo o si
  /// la petición falla, para que el mapa no parpadee ni se vacíe.
  final HeatMap? data;
  final ApiFailure? failure;
}

/// El mapa de calor de la zona visible. Hay uno por pantalla abierta.
class HeatController extends Notifier<HeatState> {
  // Cada consulta lleva un número: solo la más reciente puede cambiar el estado
  int _lastRequest = 0;
  Bbox? _lastBbox;

  @override
  HeatState build() => const HeatState();

  Future<void> load(Bbox bbox) async {
    _lastBbox = bbox;
    final request = ++_lastRequest;
    final window = state.window;
    state = HeatState(window: window, data: state.data, loading: true);

    try {
      final data = await ref.read(heatRepositoryProvider).fetch(bbox, window);
      if (!_current(request)) return;
      state = HeatState(window: window, data: data);
    } on ApiFailure catch (failure) {
      if (!_current(request)) return;
      state = HeatState(window: window, data: state.data, failure: failure);
    } on Object {
      if (!_current(request)) return;
      state = HeatState(
        window: window,
        data: state.data,
        failure: const ApiFailure.unexpected(),
      );
    }
  }

  /// Cambia la ventana y vuelve a pedir la última zona. Si todavía no se cargó
  /// ninguna, solo la recuerda.
  Future<void> setWindow(HeatWindow window) async {
    if (window == state.window) return;
    state = HeatState(window: window, data: state.data, loading: state.loading);

    final bbox = _lastBbox;
    if (bbox != null) await load(bbox);
  }

  /// Repite la última consulta (botón "Reintentar").
  Future<void> retry() async {
    final bbox = _lastBbox;
    if (bbox != null) await load(bbox);
  }

  // Una respuesta vale solo si es de la última consulta y la pantalla sigue abierta
  bool _current(int request) => request == _lastRequest && ref.mounted;
}

final heatControllerProvider =
    NotifierProvider.autoDispose<HeatController, HeatState>(HeatController.new);
