import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_controller.dart';
import 'auth_failure_message.dart';
import 'auth_widgets.dart';

/// Frame 02: iniciar sesión con alias y contraseña.
///
/// Respecto al diseño: no hay teléfono (las cuentas son anónimas), tampoco
/// "huella / passkey" (fuera del MVP) y "Reportar sin cuenta" pasó a "Ver el
/// mapa sin cuenta": sin cuenta se mira, pero reportar y votar exigen una.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({
    super.key,
    required this.onRegister,
    required this.onViewMap,
    this.onForgotPassword,
  });

  final VoidCallback onRegister;
  final VoidCallback onViewMap;

  /// Sin esto el enlace "¿Olvidaste tu contraseña?" no se muestra: solo tiene
  /// sentido si existe una forma de recuperar la cuenta.
  final VoidCallback? onForgotPassword;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _alias = TextEditingController();
  final _password = TextEditingController();

  bool _showPassword = false;
  String? _aliasError;
  String? _passwordError;

  @override
  void dispose() {
    _alias.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final alias = _alias.text.trim();
    final aliasError = alias.isEmpty ? 'Escribe tu alias.' : null;
    // La contraseña no se recorta: los espacios pueden ser parte de ella
    final passwordError = _password.text.isEmpty
        ? 'Escribe tu contraseña.'
        : null;

    setState(() {
      _aliasError = aliasError;
      _passwordError = passwordError;
    });
    if (aliasError != null || passwordError != null) return;

    await ref
        .read(authControllerProvider.notifier)
        .login(alias: alias, password: _password.text);

    if (mounted &&
        ref.read(authControllerProvider).status == AuthStatus.signedIn) {
      TextInput.finishAutofillContext();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final failure = auth.failure;
    final waiting = failure != null && waitFor(failure) != null;

    return AuthPage(
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            const Center(
              child: CircleAvatar(
                radius: 32,
                backgroundColor: Color(0xFFE0EFFF),
                child: Icon(Icons.shield_outlined, size: 32, color: authBlue),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Inicia sesión',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: authText,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Tu identidad nunca se muestra. Solo usamos tu alias.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: authMuted),
            ),
            const SizedBox(height: 24),
            AuthTextField(
              fieldKey: const Key('campo-alias'),
              label: 'Alias',
              hint: 'Ej. Halcon-Misti-482',
              controller: _alias,
              autofillHints: const [AutofillHints.username],
              textInputAction: TextInputAction.next,
              errorText: _aliasError,
              onChanged: (_) {
                if (_aliasError != null) setState(() => _aliasError = null);
              },
            ),
            const SizedBox(height: 20),
            AuthTextField(
              fieldKey: const Key('campo-contrasena'),
              label: 'Contraseña',
              controller: _password,
              obscure: !_showPassword,
              autofillHints: const [AutofillHints.password],
              textInputAction: TextInputAction.done,
              errorText: _passwordError,
              onChanged: (_) {
                if (_passwordError != null) {
                  setState(() => _passwordError = null);
                }
              },
              onSubmitted: (_) => waiting ? null : _submit(),
              suffix: TextButton(
                key: const Key('boton-mostrar-contrasena'),
                onPressed: () => setState(() => _showPassword = !_showPassword),
                child: Text(_showPassword ? 'Ocultar' : 'Mostrar'),
              ),
            ),
            if (widget.onForgotPassword != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  key: const Key('enlace-olvide-contrasena'),
                  onPressed: widget.onForgotPassword,
                  child: const Text('¿Olvidaste tu contraseña?'),
                ),
              )
            else
              const SizedBox(height: 12),
            if (failure != null) ...[
              AuthFailureNotice(
                failure: failure,
                onWaitOver: ref
                    .read(authControllerProvider.notifier)
                    .clearFailure,
              ),
              const SizedBox(height: 16),
            ],
            AuthPrimaryButton(
              buttonKey: const Key('boton-iniciar-sesion'),
              label: 'Iniciar sesión',
              busy: auth.busy,
              onPressed: waiting ? null : _submit,
            ),
            const SizedBox(height: 28),
            _ViewMapCard(onTap: widget.onViewMap),
            const SizedBox(height: 20),
            // Wrap y no Row: con la letra grande del sistema no cabe en una línea
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text(
                  '¿No tienes cuenta? ',
                  style: TextStyle(color: authMuted),
                ),
                InkWell(
                  key: const Key('enlace-registrate'),
                  onTap: widget.onRegister,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Regístrate',
                      style: TextStyle(
                        color: authBlue,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// El cuadro de "Ver el mapa sin cuenta", en el lugar del antiguo "Reportar sin
/// cuenta" del diseño.
class _ViewMapCard extends StatelessWidget {
  const _ViewMapCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFEFF6FF),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        key: const Key('boton-ver-mapa'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFBFDBFE)),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ver el mapa sin cuenta  →',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1D4ED8),
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Mira los reportes cercanos sin registrarte. Para reportar o '
                'confirmar necesitas una cuenta.',
                style: TextStyle(fontSize: 13, color: Color(0xFF1E40AF)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
