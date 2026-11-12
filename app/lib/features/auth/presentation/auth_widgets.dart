import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/network/api_failure.dart';
import 'auth_failure_message.dart';

// Colores del diseño de Figma (frames 01–04)
const authBlue = Color(0xFF007AFF);
const authText = Color(0xFF111827);
const authMuted = Color(0xFF6B7280);
const authFieldFill = Color(0xFFF9FAFB);
const authBorder = Color(0xFFE5E7EB);
const authError = Color(0xFFB91C1C);

/// El marco de las pantallas de cuenta: fondo blanco, contenido de ancho
/// limitado y centrado (en una tablet un formulario de lado a lado se vería
/// mal) y desplazable, para que el teclado no tape los campos.
class AuthPage extends StatelessWidget {
  const AuthPage({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      // Los botones de texto ("Mostrar", "Volver", "Olvidaste...") usan el azul
      // del diseño y no el del tema de la app
      body: Theme(
        data: Theme.of(context).copyWith(
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(foregroundColor: authBlue),
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Campo con la etiqueta encima, como en Figma. El error, si hay, reemplaza a
/// la ayuda.
class AuthTextField extends StatelessWidget {
  const AuthTextField({
    super.key,
    required this.fieldKey,
    required this.label,
    required this.controller,
    this.hint,
    this.helper,
    this.errorText,
    this.obscure = false,
    this.suffix,
    this.autofillHints,
    this.keyboardType,
    this.textInputAction,
    this.maxLength,
    this.onChanged,
    this.onSubmitted,
  });

  /// La llave va en el `TextField` (no en este envoltorio) para que los tests
  /// y el teclado lleguen directo al campo.
  final Key fieldKey;
  final String label;
  final TextEditingController controller;
  final String? hint;
  final String? helper;
  final String? errorText;
  final bool obscure;
  final Widget? suffix;
  final Iterable<String>? autofillHints;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final int? maxLength;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: authBorder),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: authText,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          key: fieldKey,
          controller: controller,
          obscureText: obscure,
          // Una contraseña no debe pasar por el corrector ni las sugerencias
          autocorrect: !obscure,
          enableSuggestions: !obscure,
          autofillHints: autofillHints,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          maxLength: maxLength,
          buildCounter:
              (_, {required currentLength, required isFocused, maxLength}) =>
                  null,
          style: const TextStyle(fontSize: 16, color: authText),
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: authFieldFill,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 16,
            ),
            suffixIcon: suffix,
            enabledBorder: border,
            border: border,
            focusedBorder: border.copyWith(
              borderSide: const BorderSide(color: authBlue, width: 1.5),
            ),
            errorBorder: border.copyWith(
              borderSide: const BorderSide(color: authError),
            ),
            focusedErrorBorder: border.copyWith(
              borderSide: const BorderSide(color: authError, width: 1.5),
            ),
            // El texto de error lo dibuja el propio campo: un lector de
            // pantalla lo lee junto con el campo
            errorText: errorText,
            errorMaxLines: 3,
          ),
        ),
        if (errorText == null && helper != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              helper!,
              style: const TextStyle(fontSize: 13, color: authMuted),
            ),
          ),
      ],
    );
  }
}

/// El botón azul grande. Con [busy] muestra un progreso y no responde.
class AuthPrimaryButton extends StatelessWidget {
  const AuthPrimaryButton({
    super.key,
    required this.buttonKey,
    required this.label,
    required this.onPressed,
    this.busy = false,
  });

  /// La llave va en el `FilledButton`, no en este envoltorio.
  final Key buttonKey;
  final String label;

  /// `null` lo deshabilita (por ejemplo durante la espera por un bloqueo).
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      width: double.infinity,
      child: FilledButton(
        key: buttonKey,
        onPressed: busy ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: authBlue,
          disabledBackgroundColor: authBlue.withValues(alpha: 0.45),
          foregroundColor: Colors.white,
          disabledForegroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        child: busy
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : Text(label),
      ),
    );
  }
}

/// El cuadro rojo con lo que salió mal. Si el servidor pidió esperar (cuenta
/// bloqueada, demasiadas solicitudes) muestra una cuenta regresiva y, al llegar
/// a cero, avisa con [onWaitOver] para que se quite el error y se pueda
/// reintentar.
class AuthFailureNotice extends StatefulWidget {
  const AuthFailureNotice({
    super.key,
    required this.failure,
    required this.onWaitOver,
  });

  final ApiFailure failure;
  final VoidCallback onWaitOver;

  @override
  State<AuthFailureNotice> createState() => _AuthFailureNoticeState();
}

class _AuthFailureNoticeState extends State<AuthFailureNotice> {
  Timer? _timer;
  Duration? _remaining;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(AuthFailureNotice old) {
    super.didUpdateWidget(old);
    // Un error nuevo (otro objeto) reinicia la cuenta; el mismo no
    if (!identical(old.failure, widget.failure)) _start();
  }

  void _start() {
    _timer?.cancel();
    _remaining = waitFor(widget.failure);
    if (_remaining == null) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final left = _remaining! - const Duration(seconds: 1);
      if (left <= Duration.zero) {
        _timer?.cancel();
        widget.onWaitOver();
      } else {
        setState(() => _remaining = left);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = _remaining;
    return Container(
      key: const Key('aviso-error-auth'),
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFCA5A5)),
      ),
      child: Semantics(
        liveRegion: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              authFailureMessage(widget.failure),
              style: const TextStyle(fontSize: 14, color: authError),
            ),
            if (remaining != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Podrás intentar de nuevo en ${formatCountdown(remaining)}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: authError,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
