import 'package:flutter/material.dart';

import 'auth_widgets.dart';

/// Lo que se ve mientras la app recupera la sesión guardada (un instante, o
/// unos segundos si la señal es mala).
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      key: Key('pantalla-cargando'),
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.shield_outlined, size: 56, color: authBlue),
            SizedBox(height: 24),
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          ],
        ),
      ),
    );
  }
}
