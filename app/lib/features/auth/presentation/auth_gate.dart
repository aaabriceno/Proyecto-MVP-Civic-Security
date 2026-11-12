import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_controller.dart';
import 'signed_out_flow.dart';
import 'splash_screen.dart';

/// La puerta de la app: según la sesión, muestra la pantalla de carga, las
/// pantallas de bienvenida/login/registro o el mapa.
///
/// Recibe los mapas por parámetro en vez de crearlos: así no depende del resto
/// de la app y se prueba con mapas de mentira.
class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({
    super.key,
    required this.signedInBuilder,
    required this.publicMapBuilder,
    this.offlineRetryEvery = const Duration(seconds: 30),
  });

  /// Lo que ve quien tiene sesión (o la tiene guardada pero no hay señal).
  final WidgetBuilder signedInBuilder;

  /// El mapa de solo lectura para quien aún no tiene cuenta.
  final Widget Function(BuildContext context, VoidCallback onSignIn)
  publicMapBuilder;

  /// Cada cuánto se reintenta confirmar la sesión si se abrió sin señal.
  final Duration offlineRetryEvery;

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate>
    with WidgetsBindingObserver {
  Timer? _retryTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(ref.read(authControllerProvider.notifier).restore());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _retryTimer?.cancel();
    super.dispose();
  }

  /// Al volver a la app, si la sesión quedó sin confirmar, se intenta de nuevo
  /// sin esperar al temporizador.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        ref.read(authControllerProvider).status == AuthStatus.offline) {
      unawaited(ref.read(authControllerProvider.notifier).restore());
    }
  }

  /// Mientras la sesión esté "sin confirmar" se reintenta cada cierto tiempo;
  /// en cuanto se confirma (o se pierde) el temporizador se apaga.
  void _syncRetryTimer(AuthStatus status) {
    if (status == AuthStatus.offline) {
      _retryTimer ??= Timer.periodic(
        widget.offlineRetryEvery,
        (_) => unawaited(ref.read(authControllerProvider.notifier).restore()),
      );
    } else {
      _retryTimer?.cancel();
      _retryTimer = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      authControllerProvider,
      (_, next) => _syncRetryTimer(next.status),
    );

    return switch (ref.watch(authControllerProvider).status) {
      AuthStatus.loading => const SplashScreen(),
      AuthStatus.signedOut => SignedOutFlow(
        publicMapBuilder: widget.publicMapBuilder,
      ),
      AuthStatus.signedIn ||
      AuthStatus.offline => widget.signedInBuilder(context),
    };
  }
}
