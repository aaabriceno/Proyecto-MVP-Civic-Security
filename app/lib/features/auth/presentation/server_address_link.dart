import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/civic_root.dart';
import '../../../core/config/server_address.dart';
import '../../../core/storage/token_store.dart';
import 'auth_widgets.dart';

/// "Servidor: 172.20.10.14:4000 · Cambiar". Solo se muestra en las versiones de
/// prueba (nunca en la versión final): permite instalar el mismo APK en varios
/// teléfonos y apuntarlo, ya en el lugar, al servidor de esa red.
class ServerAddressLink extends ConsumerWidget {
  const ServerAddressLink({super.key});

  Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    String current,
  ) async {
    // Se toma todo antes de esperar: al guardar, la app se rearma y este widget
    // deja de existir
    final store = ref.read(serverAddressStoreProvider);
    final tokens = ref.read(tokenStoreProvider);
    final probe = ref.read(serverHealthCheckProvider);
    final root = CivicRoot.maybeOf(context);

    final choice = await showDialog<_Choice>(
      context: context,
      builder: (_) => _ServerAddressDialog(current: current, probe: probe),
    );
    if (choice == null) return;

    switch (choice) {
      case _Save(:final url):
        await store.save(url);
      case _Reset():
        await store.clear();
    }
    // Los tokens de un servidor no sirven en otro
    await tokens.clear();
    root?.useServer(switch (choice) {
      _Save(:final url) => url,
      _Reset() => null,
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = ref.watch(serverUrlProvider);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            'Servidor: ${Uri.parse(url).authority}',
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, color: authMuted),
          ),
        ),
        TextButton(
          key: const Key('servidor-prueba'),
          onPressed: () => _open(context, ref, url),
          child: const Text('Cambiar'),
        ),
      ],
    );
  }
}

sealed class _Choice {
  const _Choice();
}

class _Save extends _Choice {
  const _Save(this.url);
  final String url;
}

class _Reset extends _Choice {
  const _Reset();
}

enum _Probe { idle, checking, responds, fails }

class _ServerAddressDialog extends StatefulWidget {
  const _ServerAddressDialog({required this.current, required this.probe});

  final String current;
  final ServerHealthCheck probe;

  @override
  State<_ServerAddressDialog> createState() => _ServerAddressDialogState();
}

class _ServerAddressDialogState extends State<_ServerAddressDialog> {
  late final _controller = TextEditingController(
    text: Uri.parse(widget.current).authority,
  );
  String? _error;
  _Probe _probe = _Probe.idle;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// La dirección escrita ya normalizada, o `null` (y el motivo en pantalla).
  String? _valid() {
    final url = normalizeServerAddress(_controller.text);
    setState(
      () => _error = url == null
          ? 'Escribe una dirección válida, por ejemplo 172.20.10.14:4000.'
          : null,
    );
    return url;
  }

  Future<void> _test() async {
    final url = _valid();
    if (url == null) return;
    setState(() => _probe = _Probe.checking);
    final ok = await widget.probe(url);
    if (!mounted) return;
    setState(() => _probe = ok ? _Probe.responds : _Probe.fails);
  }

  void _save() {
    final url = _valid();
    if (url == null) return;
    // La misma de siempre: no hay nada que cambiar (ni sesión que cerrar)
    Navigator.pop(context, url == widget.current ? null : _Save(url));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Dirección del servidor'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'La IP de la computadora que corre el servidor, en la misma red '
              'Wi-Fi que este teléfono.',
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('servidor-campo'),
              controller: _controller,
              autofocus: true,
              keyboardType: TextInputType.url,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                hintText: 'Ej. 172.20.10.14:4000',
                errorText: _error,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() => _probe = _Probe.idle),
            ),
            const SizedBox(height: 10),
            ...switch (_probe) {
              _Probe.idle => const <Widget>[],
              _Probe.checking => const [
                LinearProgressIndicator(key: Key('servidor-probando')),
              ],
              _Probe.responds => const [
                Text(
                  'El servidor responde.',
                  key: Key('servidor-responde'),
                  style: TextStyle(color: Color(0xFF15803D)),
                ),
              ],
              _Probe.fails => const [
                Text(
                  'No se pudo conectar. Revisa la IP y que el servidor esté '
                  'encendido y en la misma red.',
                  key: Key('servidor-no-responde'),
                  style: TextStyle(color: Color(0xFFB91C1C)),
                ),
              ],
            },
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('servidor-restablecer'),
          onPressed: () => Navigator.pop(context, const _Reset()),
          child: const Text('Restablecer'),
        ),
        TextButton(
          key: const Key('servidor-probar'),
          onPressed: _probe == _Probe.checking ? null : _test,
          child: const Text('Probar'),
        ),
        FilledButton(
          key: const Key('servidor-guardar'),
          onPressed: _save,
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
