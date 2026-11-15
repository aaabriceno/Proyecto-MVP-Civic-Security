import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/phone/dialer.dart';
import '../../incident/domain/incident.dart';
import 'photo_messages.dart';
import 'report_controller.dart';

const _blue = Color(0xFF0A84FF);
const _red = Color(0xFFDC2626);
const _green = Color(0xFF16A34A);

/// Frame 07. Se cierra con `true` si el usuario elige "Ver en el mapa".
class ReportSentScreen extends ConsumerWidget {
  const ReportSentScreen({super.key, required this.incident});

  final Incident incident;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(reportControllerProvider);
    final uploading = report.photo == PhotoStatus.uploading;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: _green.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check, size: 52, color: _green),
              ),
              const SizedBox(height: 20),
              Text(
                'Reporte enviado',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              // No se promete avisar a otras personas: las alertas aún no existen
              const Text(
                'Tu reporte aparecerá como "Sin verificar" hasta que 3 vecinos '
                'lo confirmen.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'Nadie, ni otros usuarios ni autoridades, puede ver quién '
                  'envió este reporte.',
                  style: TextStyle(color: Color(0xFF1E3A8A)),
                ),
              ),
              if (report.photo != PhotoStatus.none) ...[
                const SizedBox(height: 16),
                _PhotoStatusRow(
                  report: report,
                  onRetry: () =>
                      ref.read(reportControllerProvider.notifier).retryPhoto(),
                ),
              ],
              const Spacer(flex: 2),
              OutlinedButton(
                key: const Key('llamar-105'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _red,
                  side: const BorderSide(color: _red),
                  minimumSize: const Size.fromHeight(52),
                ),
                onPressed: () => ref.read(dialerProvider).dial('105'),
                child: const Text('¿Es una emergencia? Llamar al 105'),
              ),
              const SizedBox(height: 12),
              FilledButton(
                key: const Key('ver-en-el-mapa'),
                style: FilledButton.styleFrom(
                  backgroundColor: _blue,
                  minimumSize: const Size.fromHeight(52),
                ),
                // Si se sale mientras sube, un fallo pasaría sin que se vea
                onPressed: uploading
                    ? null
                    : () => Navigator.of(context).pop(true),
                child: const Text('Ver en el mapa'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Cómo va la foto del reporte: subiendo, adjunta, o por qué falló.
class _PhotoStatusRow extends StatelessWidget {
  const _PhotoStatusRow({required this.report, required this.onRetry});

  final ReportState report;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final failure = report.photoFailure;

    return Container(
      key: const Key('estado-foto'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: report.photo == PhotoStatus.failed
            ? const Color(0xFFFEF2F2)
            : const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Semantics(
        liveRegion: true,
        child: switch (report.photo) {
          PhotoStatus.uploading => const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              SizedBox(width: 10),
              Text('Subiendo la foto…'),
            ],
          ),
          PhotoStatus.uploaded => const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle, size: 18, color: _green),
              SizedBox(width: 8),
              Text('Foto adjunta'),
            ],
          ),
          PhotoStatus.failed => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  failure == null
                      ? 'No pudimos subir la foto.'
                      : photoFailureMessage(failure),
                  style: const TextStyle(color: _red),
                ),
              ),
              if (failure == null || canRetryPhoto(failure))
                TextButton(
                  key: const Key('reintentar-foto'),
                  onPressed: onRetry,
                  child: const Text('Reintentar'),
                ),
            ],
          ),
          PhotoStatus.none => const SizedBox.shrink(),
        },
      ),
    );
  }
}
