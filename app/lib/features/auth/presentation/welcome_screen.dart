import 'package:flutter/material.dart';

import '../../map/presentation/incident_style.dart';
import '../../incident/domain/incident.dart';
import 'auth_widgets.dart';

/// Frame 01: la primera pantalla de quien no tiene sesión.
///
/// El diseño usaba una captura de Google Maps (no se puede usar su contenido
/// así) y tenía erratas ("manter", "poblacion"): aquí la ilustración se dibuja
/// en código y el texto está corregido.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key, required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // La ilustración ocupa la mitad de la pantalla; el texto y el botón
            // se centran en lo que queda. En una pantalla baja o con letra
            // grande el contenido no cabe y se desplaza, en vez de desbordarse.
            final illustrationHeight = constraints.maxHeight * 0.5;
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Column(
                    children: [
                      _Illustration(height: illustrationHeight),
                      Expanded(child: _Greeting(onStart: onStart)),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Illustration extends StatelessWidget {
  const _Illustration({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: double.infinity,
      color: const Color(0xFFF3F3F3),
      padding: EdgeInsets.fromLTRB(
        32,
        MediaQuery.paddingOf(context).top + 24,
        32,
        24,
      ),
      child: Center(
        child: AspectRatio(
          aspectRatio: 0.72,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: const CustomPaint(
              key: Key('ilustracion-bienvenida'),
              painter: _MapIllustrationPainter(),
            ),
          ),
        ),
      ),
    );
  }
}

/// El saludo y el botón "Comenzar".
class _Greeting extends StatelessWidget {
  const _Greeting({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Bienvenido a',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: authText,
                ),
              ),
              const Text(
                'CIVIC SECURITY',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  color: authText,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Esta es una aplicación enfocada en el apoyo entre ciudadanos '
                'para mantener a la población alerta.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: authMuted, height: 1.4),
              ),
              const SizedBox(height: 28),
              AuthPrimaryButton(
                buttonKey: const Key('boton-comenzar'),
                label: 'Comenzar',
                onPressed: onStart,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Un mapa de ciudad estilizado: manzanas, un río, un parque, dos avenidas y
/// pines de los colores de los tipos de incidente. No representa ningún lugar
/// real; solo da la idea de la app sin usar el mapa de nadie.
class _MapIllustrationPainter extends CustomPainter {
  const _MapIllustrationPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFEAEFF4),
    );

    // Parque
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.08, h * 0.10, w * 0.30, h * 0.18),
        const Radius.circular(10),
      ),
      Paint()..color = const Color(0xFFCFEBD6),
    );

    // Río
    final river = Path()
      ..moveTo(w * 0.62, 0)
      ..cubicTo(w * 0.45, h * 0.25, w * 0.85, h * 0.50, w * 0.55, h);
    canvas.drawPath(
      river,
      Paint()
        ..color = const Color(0xFFBFD9F2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.07
        ..strokeCap = StrokeCap.round,
    );

    // Calles
    final street = Paint()
      ..color = Colors.white
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    for (var i = 1; i <= 6; i++) {
      final y = h * i / 7;
      canvas.drawLine(
        Offset(0, y),
        Offset(w, y + (i.isEven ? 10 : -10)),
        street,
      );
    }
    for (var i = 1; i <= 4; i++) {
      final x = w * i / 5;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x + (i.isOdd ? 12 : -12), h),
        street,
      );
    }
    // Avenidas
    final avenue = Paint()
      ..color = const Color(0xFFFFE9B8)
      ..strokeWidth = 11
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(0, h * 0.78), Offset(w, h * 0.30), avenue);
    canvas.drawLine(Offset(w * 0.12, h), Offset(w * 0.30, 0), avenue);

    // Pines
    const pines = [
      (0.26, 0.36, IncidentType.robo),
      (0.52, 0.22, IncidentType.peleaColegio),
      (0.74, 0.46, IncidentType.maltratoAnimal),
      (0.40, 0.62, IncidentType.actividadSospechosa),
      (0.68, 0.76, IncidentType.agresionMujer),
      (0.18, 0.80, IncidentType.otro),
    ];
    for (final (x, y, type) in pines) {
      final center = Offset(w * x, h * y);
      canvas
        ..drawCircle(
          center.translate(0, 2),
          14,
          Paint()..color = const Color(0x33000000),
        )
        ..drawCircle(center, 14, Paint()..color = Colors.white)
        ..drawCircle(center, 11, Paint()..color = typeColor(type))
        ..drawCircle(center, 3.5, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(_MapIllustrationPainter old) => false;
}
