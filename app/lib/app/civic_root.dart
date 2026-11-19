import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import '../core/config/server_address.dart';
import 'app.dart';

/// La raíz de la app: el [ProviderScope] y, sobre él, la dirección del servidor.
///
/// Cambiar de servidor no se hace "en caliente": [useServer] rearma **toda** la
/// app (un [ProviderScope] nuevo), así ningún cliente HTTP, canal en vivo ni
/// sesión se queda hablando con el servidor anterior.
class CivicRoot extends StatefulWidget {
  const CivicRoot({
    super.key,
    this.initialServerUrl,
    this.overrides = const [],
    this.child = const CivicApp(),
  });

  /// La dirección guardada de una apertura anterior; `null` usa la de compilación.
  final String? initialServerUrl;

  /// Solo para pruebas: reemplazos de proveedores.
  final List<Override> overrides;

  final Widget child;

  /// La raíz que contiene a [context], si la hay.
  static CivicRootState? maybeOf(BuildContext context) =>
      context.findAncestorStateOfType<CivicRootState>();

  @override
  State<CivicRoot> createState() => CivicRootState();
}

class CivicRootState extends State<CivicRoot> {
  late String? _serverUrl = widget.initialServerUrl;
  Key _scopeKey = UniqueKey();

  /// Rearma la app hablando con [url] (`null` vuelve a la de compilación).
  void useServer(String? url) => setState(() {
    _serverUrl = url;
    _scopeKey = UniqueKey();
  });

  @override
  Widget build(BuildContext context) {
    final url = _serverUrl;
    return ProviderScope(
      key: _scopeKey,
      overrides: [
        ...widget.overrides,
        if (url != null) serverUrlProvider.overrideWithValue(url),
      ],
      child: widget.child,
    );
  }
}
