import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_failure.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../auth/presentation/auth_failure_message.dart';
import '../../auth/presentation/auth_widgets.dart';
import '../data/account_service.dart';
import 'profile_page.dart';

/// Borrar la cuenta (Ley N.º 29733: derecho de cancelación). Pide la contraseña
/// y una casilla de "entiendo", para que no se haga por accidente.
///
/// Los reportes no se borran: no están enlazados a la cuenta y son información de
/// seguridad pública. La pantalla lo dice con claridad antes de que se confirme.
class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  ConsumerState<DeleteAccountScreen> createState() =>
      _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  final _password = TextEditingController();

  bool _show = false;
  bool _understood = false;
  bool _busy = false;
  ApiFailure? _failure;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  bool get _ready => _understood && _password.text.isNotEmpty;

  Future<void> _delete() async {
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      await ref
          .read(accountServiceProvider)
          .deleteAccount(password: _password.text);
      // La cuenta ya no existe: se cierra la sesión de este teléfono y la puerta
      // de entrada lleva a la bienvenida
      await ref.read(authControllerProvider.notifier).logout();
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
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
    final passwordError = fieldErrorOf(failure, 'password') == null
        ? null
        : 'La contraseña no es correcta.';

    return ProfilePage(
      title: 'Borrar mi cuenta',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          const _Bullet(
            icon: Icons.delete_outline,
            text:
                'Se borran tu alias, tu contraseña, tu consentimiento y tus '
                'sesiones. Esto no se puede deshacer.',
          ),
          const _Bullet(
            icon: Icons.map_outlined,
            text:
                'Tus reportes seguirán en el mapa, sin ningún vínculo contigo: '
                'nadie, tampoco nosotros, puede saber que eran tuyos.',
          ),
          const _Bullet(
            icon: Icons.person_add_alt_outlined,
            text: 'Tu alias quedará libre: otra persona podría usarlo.',
          ),
          const SizedBox(height: 16),
          AuthTextField(
            fieldKey: const Key('campo-contrasena'),
            label: 'Tu contraseña',
            controller: _password,
            obscure: !_show,
            textInputAction: TextInputAction.done,
            errorText: passwordError,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => (_ready && !waiting) ? _delete() : null,
            suffix: TextButton(
              key: const Key('boton-mostrar-contrasena'),
              onPressed: () => setState(() => _show = !_show),
              child: Text(_show ? 'Ocultar' : 'Mostrar'),
            ),
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            key: const Key('checkbox-entiendo'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _understood,
            onChanged: _busy
                ? null
                : (value) => setState(() => _understood = value ?? false),
            title: const Text(
              'Entiendo que no se puede deshacer.',
              style: TextStyle(fontSize: 15),
            ),
          ),
          const SizedBox(height: 8),
          if (failure != null && passwordError == null) ...[
            AuthFailureNotice(
              failure: failure,
              onWaitOver: () => setState(() => _failure = null),
            ),
            const SizedBox(height: 16),
          ],
          SizedBox(
            height: 52,
            child: FilledButton(
              key: const Key('boton-borrar-cuenta'),
              onPressed: (_ready && !_busy && !waiting) ? _delete : null,
              style: FilledButton.styleFrom(
                backgroundColor: authError,
                foregroundColor: Colors.white,
                disabledBackgroundColor: authError.withValues(alpha: 0.35),
                disabledForegroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: _busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Borrar mi cuenta'),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            key: const Key('boton-cancelar-borrado'),
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: authMuted),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 15, color: authText),
            ),
          ),
        ],
      ),
    );
  }
}
