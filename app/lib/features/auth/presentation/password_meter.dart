import 'package:flutter/material.dart';

import '../domain/password_strength.dart';
import 'auth_widgets.dart';

/// Medidor de 4 segmentos bajo el campo de contraseña (frame 03).
///
/// Mide solo el largo (ver [PasswordStrength]) y siempre recuerda el mínimo y
/// que una frase fácil de recordar sirve más que símbolos.
class PasswordMeter extends StatelessWidget {
  const PasswordMeter({super.key, required this.strength});

  final PasswordStrength strength;

  static const _hint =
      'Mín. $minPasswordLength caracteres. '
      'Usa una frase fácil de recordar.';

  @override
  Widget build(BuildContext context) {
    final color = _color(strength);
    final label = _label(strength);

    return Column(
      key: const Key('medidor-contrasena'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (var i = 0; i < 4; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: i < strength.segments ? color : authBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        if (label != null)
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        Text(
          _hint,
          style: TextStyle(
            fontSize: 13,
            color: label == null ? authMuted : color,
          ),
        ),
      ],
    );
  }

  static String? _label(PasswordStrength s) => switch (s) {
    PasswordStrength.empty => null,
    PasswordStrength.veryShort => 'Muy corta',
    PasswordStrength.short => 'Corta',
    PasswordStrength.acceptable => 'Aceptable',
    PasswordStrength.good => 'Buena',
  };

  static Color _color(PasswordStrength s) => switch (s) {
    PasswordStrength.empty => authMuted,
    PasswordStrength.veryShort => const Color(0xFFDC2626),
    PasswordStrength.short ||
    PasswordStrength.acceptable => const Color(0xFFF59E0B),
    PasswordStrength.good => const Color(0xFF16A34A),
  };
}
