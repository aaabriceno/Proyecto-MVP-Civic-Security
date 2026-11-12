import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/alias_suggester.dart';
import '../domain/password_strength.dart';
import 'auth_controller.dart';
import 'auth_failure_message.dart';
import 'auth_widgets.dart';
import 'password_meter.dart';

/// Frame 03: crear una cuenta anónima. Solo se pide alias y contraseña.
///
/// Al registrarse bien, el estado de la sesión pasa a `signedIn` y quien
/// muestra esta pantalla (la puerta de entrada) cambia sola a lo que sigue.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key, required this.onBack, this.suggester});

  final VoidCallback onBack;

  /// Solo para tests: un generador con semilla fija.
  final AliasSuggester? suggester;

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  late final AliasSuggester _suggester = widget.suggester ?? AliasSuggester();
  late final _alias = TextEditingController(text: _suggester.next());
  final _password = TextEditingController();

  bool _showPassword = false;
  bool _consent = false;

  // Errores de los datos, antes de molestar al servidor
  String? _aliasError;
  String? _passwordError;
  String? _consentError;

  @override
  void dispose() {
    _alias.dispose();
    _password.dispose();
    super.dispose();
  }

  void _anotherAlias() {
    setState(() {
      _alias.text = _suggester.next(anterior: _alias.text);
      _aliasError = null;
    });
  }

  Future<void> _submit() async {
    final alias = _alias.text.trim();
    final aliasError = isValidAlias(alias)
        ? null
        : 'Usa de 3 a 20 letras sin tilde, números, guion, guion bajo o punto.';
    final passwordError = passwordStrengthOf(_password.text).meetsMinimum
        ? null
        : 'Debe tener al menos $minPasswordLength caracteres.';
    final consentError = _consent
        ? null
        : 'Debes aceptar para crear la cuenta.';

    setState(() {
      _aliasError = aliasError;
      _passwordError = passwordError;
      _consentError = consentError;
    });
    if (aliasError != null || passwordError != null || consentError != null) {
      return;
    }

    await ref
        .read(authControllerProvider.notifier)
        .register(alias: alias, password: _password.text, acceptsConsent: true);

    // Con la cuenta creada, el gestor de contraseñas ofrece guardarla
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
    // Si el servidor marcó campos, el error sale bajo cada campo y no hace
    // falta además el cuadro general
    final fieldErrors = failure != null && failure.fields.isNotEmpty;

    return AuthPage(
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextButton.icon(
              onPressed: widget.onBack,
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('Volver'),
            ),
            const SizedBox(height: 8),
            const Text(
              'Crea tu cuenta anónima',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: authText,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'No pedimos nombre ni apellido. Los demás solo verán tu alias.',
              style: TextStyle(fontSize: 16, color: authMuted),
            ),
            const SizedBox(height: 24),
            AuthTextField(
              fieldKey: const Key('campo-alias'),
              label: 'Alias público',
              controller: _alias,
              maxLength: 20,
              autofillHints: const [AutofillHints.newUsername],
              textInputAction: TextInputAction.next,
              errorText: _aliasError ?? fieldErrorOf(failure, 'alias'),
              helper:
                  'Generado al azar. Puedes cambiarlo; no uses tu nombre real.',
              onChanged: (_) {
                if (_aliasError != null) setState(() => _aliasError = null);
              },
              suffix: Padding(
                padding: const EdgeInsets.all(8),
                child: ActionChip(
                  key: const Key('boton-otro-alias'),
                  avatar: const Icon(Icons.refresh, size: 16, color: authBlue),
                  label: const Text('Otro'),
                  labelStyle: const TextStyle(
                    color: authBlue,
                    fontWeight: FontWeight.w600,
                  ),
                  backgroundColor: const Color(0xFFE0EDFB),
                  side: BorderSide.none,
                  onPressed: _anotherAlias,
                ),
              ),
            ),
            const SizedBox(height: 20),
            AuthTextField(
              fieldKey: const Key('campo-contrasena'),
              label: 'Contraseña',
              controller: _password,
              obscure: !_showPassword,
              autofillHints: const [AutofillHints.newPassword],
              textInputAction: TextInputAction.done,
              errorText: _passwordError ?? fieldErrorOf(failure, 'password'),
              onChanged: (_) => setState(() => _passwordError = null),
              onSubmitted: (_) => waiting ? null : _submit(),
              suffix: TextButton(
                key: const Key('boton-mostrar-contrasena'),
                onPressed: () => setState(() => _showPassword = !_showPassword),
                child: Text(_showPassword ? 'Ocultar' : 'Mostrar'),
              ),
            ),
            const SizedBox(height: 10),
            PasswordMeter(strength: passwordStrengthOf(_password.text)),
            const SizedBox(height: 20),
            _ConsentRow(
              value: _consent,
              error:
                  _consentError ??
                  fieldErrorOf(failure, 'acepta_consentimiento'),
              onChanged: (value) => setState(() {
                _consent = value;
                _consentError = null;
              }),
            ),
            const SizedBox(height: 16),
            if (failure != null && !fieldErrors) ...[
              AuthFailureNotice(
                failure: failure,
                onWaitOver: ref
                    .read(authControllerProvider.notifier)
                    .clearFailure,
              ),
              const SizedBox(height: 16),
            ],
            AuthPrimaryButton(
              buttonKey: const Key('boton-crear-cuenta'),
              label: 'Crear cuenta',
              busy: auth.busy,
              onPressed: waiting ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}

class _ConsentRow extends StatelessWidget {
  const _ConsentRow({
    required this.value,
    required this.error,
    required this.onChanged,
  });

  final bool value;
  final String? error;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => onChanged(!value),
          borderRadius: BorderRadius.circular(8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                key: const Key('checkbox-consentimiento'),
                value: value,
                activeColor: authBlue,
                onChanged: (v) => onChanged(v ?? false),
              ),
              const Expanded(
                child: Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(
                    'Acepto los Términos y la Política de Privacidad '
                    '(Ley N.º 29733).',
                    style: TextStyle(fontSize: 14, color: authText),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(left: 12, top: 2),
            child: Text(
              error!,
              style: const TextStyle(fontSize: 13, color: authError),
            ),
          ),
      ],
    );
  }
}
