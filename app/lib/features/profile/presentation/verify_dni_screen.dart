import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_failure.dart';
import '../../auth/presentation/auth_failure_message.dart';
import '../../auth/presentation/auth_widgets.dart';
import '../data/account_service.dart';
import 'profile_page.dart';

const _largoDni = 8;

/// Verificar la cuenta con el DNI.
///
/// El servidor no guarda el número: calcula una huella irreversible y solo
/// recuerda si esa huella ya tiene cuenta ("una persona, una cuenta"). Aquí el
/// número no se guarda en ningún lado, ni siquiera en el teléfono.
///
/// Cierra con `true` cuando la cuenta quedó verificada (o ya lo estaba), para
/// que el perfil se vuelva a pedir.
class VerifyDniScreen extends ConsumerStatefulWidget {
  const VerifyDniScreen({super.key});

  @override
  ConsumerState<VerifyDniScreen> createState() => _VerifyDniScreenState();
}

class _VerifyDniScreenState extends ConsumerState<VerifyDniScreen> {
  final _dni = TextEditingController();

  bool _busy = false;
  String? _localError;
  ApiFailure? _failure;

  @override
  void dispose() {
    _dni.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final dni = _dni.text;
    if (dni.length != _largoDni) {
      setState(() => _localError = _mensajeFormato);
      return;
    }

    setState(() {
      _localError = null;
      _busy = true;
      _failure = null;
    });
    try {
      await ref.read(accountServiceProvider).verifyDni(dni);
      if (!mounted) return;
      _cerrar('Cuenta verificada. Ya puedes reportar más veces al día.');
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      // Si ya estaba verificada (desde otro dispositivo), no hay nada que
      // corregir: se vuelve y el perfil se actualiza
      if (failure.code == 'already_verified') {
        _cerrar('Tu cuenta ya está verificada.');
        return;
      }
      setState(() {
        _busy = false;
        _failure = failure;
      });
    } on Object {
      if (mounted) {
        setState(() {
          _busy = false;
          _failure = const ApiFailure.unexpected();
        });
      }
    }
  }

  void _cerrar(String mensaje) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(mensaje)));
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final failure = _failure;
    final sinIntentos = failure?.code == 'dni_attempts_exceeded';
    final waiting = failure != null && waitFor(failure) != null;
    final fieldError = _localError ?? _fieldErrorOf(failure);

    return ProfilePage(
      title: 'Verificar mi cuenta',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          const Text(
            'Con la cuenta verificada puedes hacer más reportes al día.',
            style: TextStyle(fontSize: 15, color: authMuted),
          ),
          const SizedBox(height: 16),
          const _PrivacyNotice(),
          const SizedBox(height: 20),
          AuthTextField(
            fieldKey: const Key('campo-dni'),
            label: 'Número de DNI',
            hint: '8 dígitos',
            controller: _dni,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            maxLength: _largoDni,
            suggestions: false,
            // `maxLength` ya corta a 8; aquí se descarta todo lo que no sea dígito
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            errorText: fieldError,
            onChanged: (_) => setState(() {
              _localError = null;
              // El error de este campo ya no aplica al número corregido; los
              // demás (sin intentos, sin conexión) siguen
              if (_fieldErrorOf(_failure) != null) _failure = null;
            }),
            onSubmitted: (_) => sinIntentos || waiting ? null : _submit(),
          ),
          const SizedBox(height: 12),
          const Text(
            'Usar el DNI de otra persona es un delito. Tienes pocos intentos '
            'por día.',
            style: TextStyle(fontSize: 13, color: authMuted),
          ),
          const SizedBox(height: 20),
          if (failure != null && _fieldErrorOf(failure) == null) ...[
            if (sinIntentos)
              const _Notice(
                'Llegaste al límite de intentos de hoy. Vuelve a intentarlo '
                'mañana.',
              )
            else
              AuthFailureNotice(
                failure: failure,
                onWaitOver: () => setState(() => _failure = null),
              ),
            const SizedBox(height: 16),
          ],
          AuthPrimaryButton(
            buttonKey: const Key('boton-verificar-dni'),
            label: 'Verificar',
            busy: _busy,
            onPressed: sinIntentos || waiting ? null : _submit,
          ),
        ],
      ),
    );
  }
}

const _mensajeFormato = 'Escribe los 8 dígitos de tu DNI.';

/// El error del servidor que pertenece al campo del DNI, si lo hay. Los textos
/// son propios: nunca se repite lo que escribió la persona ni lo que dice el
/// servidor.
String? _fieldErrorOf(ApiFailure? failure) {
  if (failure == null) return null;
  if (failure.code == 'dni_taken') return 'Este DNI ya tiene una cuenta.';
  if (failure.code == 'validation_failed' &&
      fieldErrorOf(failure, 'dni') != null) {
    return _mensajeFormato;
  }
  return null;
}

class _PrivacyNotice extends StatelessWidget {
  const _PrivacyNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('aviso-privacidad-dni'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline, color: authBlue),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'No guardamos tu DNI ni tu nombre. Solo una huella irreversible '
              'del número, para saber si ya tiene una cuenta. Tus reportes '
              'siguen siendo anónimos: la huella no se enlaza con ellos.',
              style: TextStyle(fontSize: 14, color: authText),
            ),
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('aviso-dni'),
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFCA5A5)),
      ),
      child: Semantics(
        liveRegion: true,
        child: Text(
          text,
          style: const TextStyle(fontSize: 14, color: authError),
        ),
      ),
    );
  }
}
