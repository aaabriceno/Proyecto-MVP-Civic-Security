import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_controller.dart';
import 'login_screen.dart';
import 'register_screen.dart';
import 'welcome_screen.dart';

enum _Screen { welcome, login, register, publicMap }

/// Las pantallas de quien no tiene sesión: bienvenida → inicio de sesión ⇄
/// registro, y el mapa público de solo lectura.
///
/// No usa `Navigator`: es un solo widget que cambia de pantalla. Así, cuando la
/// sesión se abre, quien lo muestra (la puerta) lo reemplaza por completo y no
/// queda ninguna pantalla de login "debajo" del mapa.
class SignedOutFlow extends ConsumerStatefulWidget {
  const SignedOutFlow({super.key, required this.publicMapBuilder});

  /// El mapa de solo lectura; `onSignIn` vuelve al inicio de sesión.
  final Widget Function(BuildContext context, VoidCallback onSignIn)
  publicMapBuilder;

  @override
  ConsumerState<SignedOutFlow> createState() => _SignedOutFlowState();
}

class _SignedOutFlowState extends ConsumerState<SignedOutFlow> {
  _Screen _screen = _Screen.welcome;

  void _go(_Screen screen) {
    // El error de un formulario no debe aparecer en el otro
    ref.read(authControllerProvider.notifier).clearFailure();
    setState(() => _screen = screen);
  }

  /// A dónde lleva el botón atrás del sistema (`null` en la primera pantalla,
  /// donde sí se sale de la app).
  _Screen? get _previous => switch (_screen) {
    _Screen.welcome => null,
    _Screen.login => _Screen.welcome,
    _Screen.register || _Screen.publicMap => _Screen.login,
  };

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _previous == null,
      onPopInvokedWithResult: (didPop, _) {
        final previous = _previous;
        if (!didPop && previous != null) _go(previous);
      },
      child: switch (_screen) {
        _Screen.welcome => WelcomeScreen(onStart: () => _go(_Screen.login)),
        _Screen.login => LoginScreen(
          onRegister: () => _go(_Screen.register),
          onViewMap: () => _go(_Screen.publicMap),
        ),
        _Screen.register => RegisterScreen(onBack: () => _go(_Screen.login)),
        _Screen.publicMap => widget.publicMapBuilder(
          context,
          () => _go(_Screen.login),
        ),
      },
    );
  }
}
