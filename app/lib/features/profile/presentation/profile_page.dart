import 'package:flutter/material.dart';

import '../../auth/presentation/auth_widgets.dart';

/// El marco de las pantallas del perfil: barra con "atrás", fondo blanco, el
/// contenido centrado y con un ancho cómodo en una tablet.
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        foregroundColor: authText,
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700, color: authText),
        ),
      ),
      // Los botones de texto usan el azul del diseño, como en las pantallas de
      // cuenta
      body: Theme(
        data: Theme.of(context).copyWith(
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(foregroundColor: authBlue),
          ),
        ),
        child: SafeArea(
          // Arriba y no centrado: en una tablet un formulario centrado en vertical
          // deja un gran hueco encima y el teclado lo empuja fuera de la vista
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
