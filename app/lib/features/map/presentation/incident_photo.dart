import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../incident/data/incident_repository.dart';

/// La foto de un reporte, pedida al servidor cuando se abre el detalle. Se
/// descarta al cerrarlo; sin reintento automático (la pantalla ofrece el botón).
final incidentPhotoProvider = FutureProvider.autoDispose
    .family<Uint8List, String>(
      (ref, incidentId) =>
          ref.watch(incidentRepositoryProvider).fetchPhoto(incidentId),
      retry: (_, _) => null,
    );

/// La foto en el detalle de un reporte: carga, error con "Reintentar", o la
/// imagen (que se abre en grande al tocarla).
class IncidentPhoto extends ConsumerWidget {
  const IncidentPhoto({super.key, required this.incidentId});

  final String incidentId;

  static const _height = 260.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photo = ref.watch(incidentPhotoProvider(incidentId));

    return photo.when(
      loading: () => _frame(
        key: const Key('foto-cargando'),
        child: const Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => _frame(
        key: const Key('foto-error'),
        child: Row(
          children: [
            const SizedBox(width: 16),
            const Expanded(child: Text('No pudimos cargar la foto.')),
            TextButton(
              key: const Key('reintentar-foto-incidente'),
              onPressed: () =>
                  ref.invalidate(incidentPhotoProvider(incidentId)),
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
      data: (bytes) => GestureDetector(
        onTap: () => _openFullScreen(context, bytes),
        child: Container(
          height: _height,
          width: double.infinity,
          decoration: BoxDecoration(
            color: const Color(0xFFF3F4F6),
            borderRadius: BorderRadius.circular(12),
          ),
          clipBehavior: Clip.antiAlias,
          // `contain`: la foto se ve entera (una foto vertical no se recorta);
          // una evidencia no debe perder partes de la escena
          child: Image.memory(
            bytes,
            key: const Key('foto-incidente'),
            fit: BoxFit.contain,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) =>
                const Center(child: Icon(Icons.broken_image_outlined)),
          ),
        ),
      ),
    );
  }

  Widget _frame({required Key key, required Widget child}) => Container(
    key: key,
    height: _height,
    width: double.infinity,
    decoration: BoxDecoration(
      color: const Color(0xFFF3F4F6),
      borderRadius: BorderRadius.circular(12),
    ),
    child: child,
  );

  void _openFullScreen(BuildContext context, Uint8List bytes) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog.fullscreen(
        key: const Key('foto-pantalla-completa'),
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                maxScale: 5,
                child: Center(child: Image.memory(bytes)),
              ),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  key: const Key('cerrar-foto'),
                  tooltip: 'Cerrar',
                  color: Colors.white,
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
