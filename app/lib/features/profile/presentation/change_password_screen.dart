import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_failure.dart';
import '../../auth/domain/password_strength.dart';
import '../../auth/presentation/auth_failure_message.dart';
import '../../auth/presentation/auth_widgets.dart';
import '../../auth/presentation/password_meter.dart';
import '../data/account_service.dart';
import 'profile_page.dart';

/// Cambiar la contraseña. Pide la actual (aunque ya haya sesión: así quien tome
/// el teléfono prestado no puede cambiarla) y una nueva con el mismo medidor del
/// registro. Al terminar, el servidor cierra todas las demás sesiones.
class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _current = TextEditingController();
  final _next = TextEditingController();

  bool _show = false;
  bool _busy = false;
  String? _currentError;
  String? _nextError;
  ApiFailure? _failure;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final current = _current.text;
    final next = _next.text;

    final currentError = current.isEmpty
        ? 'Escribe tu contraseña actual.'
        : null;
    final nextError = !passwordStrengthOf(next).meetsMinimum
        ? 'Usa al menos $minPasswordLength caracteres.'
        : next == current
        ? 'La nueva debe ser distinta de la actual.'
        : null;

    setState(() {
      _currentError = currentError;
      _nextError = nextError;
    });
    if (currentError != null || nextError != null) return;

    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      await ref
          .read(accountServiceProvider)
          .changePassword(current: current, next: next);
      if (!mounted) return;
      // Para que el gestor de contraseñas ofrezca actualizar la guardada
      TextInput.finishAutofillContext();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Contraseña cambiada. Cerramos tus otras sesiones.'),
        ),
      );
      Navigator.of(context).pop(true);
    } on ApiFailure catch (failure) {
      if (mounted) {
        setState(() {
          _busy = false;
          _failure = failure;
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _busy = false;
          _failure = const ApiFailure.unexpected();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final failure = _failure;
    final waiting = failure != null && waitFor(failure) != null;

    // Un error de campo del servidor se muestra en su campo con texto propio
    final serverCurrent = fieldErrorOf(failure, 'current_password') == null
        ? null
        : 'La contraseña actual no es correcta.';
    final serverNextRaw = fieldErrorOf(failure, 'new_password');
    final serverNext = serverNextRaw == null
        ? null
        : 'La contraseña nueva $serverNextRaw.';
    final hasFieldError = serverCurrent != null || serverNext != null;

    return ProfilePage(
      title: 'Cambiar contraseña',
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            const Text(
              'Al cambiarla cerramos tu sesión en todos los demás dispositivos.',
              style: TextStyle(fontSize: 15, color: authMuted),
            ),
            const SizedBox(height: 20),
            AuthTextField(
              fieldKey: const Key('campo-contrasena-actual'),
              label: 'Contraseña actual',
              controller: _current,
              obscure: !_show,
              autofillHints: const [AutofillHints.password],
              textInputAction: TextInputAction.next,
              errorText: _currentError ?? serverCurrent,
              onChanged: (_) {
                if (_currentError != null) setState(() => _currentError = null);
              },
            ),
            const SizedBox(height: 20),
            AuthTextField(
              fieldKey: const Key('campo-contrasena-nueva'),
              label: 'Contraseña nueva',
              controller: _next,
              obscure: !_show,
              autofillHints: const [AutofillHints.newPassword],
              textInputAction: TextInputAction.done,
              errorText: _nextError ?? serverNext,
              onChanged: (_) => setState(() => _nextError = null),
              onSubmitted: (_) => waiting ? null : _submit(),
              suffix: TextButton(
                key: const Key('boton-mostrar-contrasenas'),
                onPressed: () => setState(() => _show = !_show),
                child: Text(_show ? 'Ocultar' : 'Mostrar'),
              ),
            ),
            const SizedBox(height: 10),
            PasswordMeter(strength: passwordStrengthOf(_next.text)),
            const SizedBox(height: 20),
            if (failure != null && !hasFieldError) ...[
              AuthFailureNotice(
                failure: failure,
                onWaitOver: () => setState(() => _failure = null),
              ),
              const SizedBox(height: 16),
            ],
            AuthPrimaryButton(
              buttonKey: const Key('boton-cambiar-contrasena'),
              label: 'Cambiar contraseña',
              busy: _busy,
              onPressed: waiting ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}
