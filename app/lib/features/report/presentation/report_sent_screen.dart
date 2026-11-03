import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/phone/dialer.dart';
import '../../incident/domain/incident.dart';

const _blue = Color(0xFF0A84FF);
const _red = Color(0xFFDC2626);
const _green = Color(0xFF16A34A);

/// Frame 07. Se cierra con `true` si el usuario elige "Ver en el mapa".
class ReportSentScreen extends ConsumerWidget {
  const ReportSentScreen({super.key, required this.incident});

  final Incident incident;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Ver en el mapa'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
