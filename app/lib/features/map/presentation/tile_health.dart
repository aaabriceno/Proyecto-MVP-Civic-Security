import 'dart:async';

import 'package:flutter/material.dart';

/// Lleva la cuenta de los mosaicos (las "baldosas" del mapa) que no se pudieron
/// descargar, para avisar a la persona cuando el mapa quedó incompleto.
///
/// Sin esto un mosaico caído se queda como un hueco gris y no hay forma de saber
/// si es la conexión, el servidor de mapas o un error de la app. Un mosaico
/// suelto que falla es normal (una señal que parpadea), así que solo se avisa a
/// partir de [threshold] fallas dentro de [window]; cada falla se olvida sola
/// pasado ese tiempo.
class TileHealth extends ChangeNotifier {
  TileHealth({this.threshold = 3, this.window = const Duration(seconds: 45)});

  /// Cuántas fallas seguidas se consideran un problema del mapa.
  final int threshold;

  /// Cuánto tiempo cuenta una falla.
  final Duration window;

  final _pending = <Timer>{};
  bool _disposed = false;

  /// ¿Hay suficientes fallas recientes como para avisar?
  bool get failing => _pending.length >= threshold;

  /// Anota un mosaico que no se pudo descargar.
  void report() {
    if (_disposed) return;
    final wasFailing = failing;
    late final Timer timer;
    timer = Timer(window, () {
      if (_disposed) return;
      final before = failing;
      _pending.remove(timer);
      if (failing != before) notifyListeners();
    });
    _pending.add(timer);
    if (failing != wasFailing) notifyListeners();
  }

  /// Borra las fallas anotadas (al reintentar: lo anterior ya no cuenta).
  void clear() {
    if (_disposed || _pending.isEmpty) return;
    final wasFailing = failing;
    for (final timer in _pending) {
      timer.cancel();
    }
    _pending.clear();
    if (wasFailing) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final timer in _pending) {
      timer.cancel();
    }
    _pending.clear();
    super.dispose();
  }
}

/// El aviso "el mapa quedó incompleto", con un botón para reintentar. No ocupa
/// nada mientras no haya fallas.
class TileErrorBanner extends StatelessWidget {
  const TileErrorBanner({
    super.key,
    required this.health,
    required this.onRetry,
  });

  final TileHealth health;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: health,
      builder: (context, _) {
        if (!health.failing) return const SizedBox.shrink();
        return Card(
          key: const Key('aviso-mosaicos'),
          margin: const EdgeInsets.only(top: 8),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
            child: Row(
              children: [
                const Icon(Icons.cloud_off_outlined, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  // Un lector de pantalla lo anuncia al aparecer
                  child: Semantics(
                    liveRegion: true,
                    child: const Text(
                      'Algunas partes del mapa no cargaron. Revisa tu '
                      'conexión.',
                    ),
                  ),
                ),
                TextButton(
                  key: const Key('boton-reintentar-mosaicos'),
                  onPressed: onRetry,
                  child: const Text('Reintentar'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
