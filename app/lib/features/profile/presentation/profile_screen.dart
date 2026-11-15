import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/domain/auth_models.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../auth/presentation/auth_widgets.dart';
import '../data/account_service.dart';
import 'change_password_screen.dart';
import 'delete_account_screen.dart';
import 'profile_format.dart';
import 'verify_dni_screen.dart';

const _fondo = Color(0xFFF7F8FA);
const _verde = Color(0xFF15803D);
const _ambar = Color(0xFFB26A00);

/// Frame 10: el perfil.
///
/// Respecto al diseño, solo está lo que ya existe en el producto: no hay
/// confirmaciones ni confiabilidad (dependen de la validación comunitaria), ni
/// código de recuperación, ni huella, ni zonas y radio de alertas. En cambio hay
/// lo que la Ley N.º 29733 pide: qué se guarda de la persona y cómo borrarlo.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    await ref.read(authControllerProvider.notifier).logout();
    // Las pantallas apiladas encima de la puerta de entrada no se van solas
    if (context.mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  // Al verificarse, el perfil que se ve ya no es el del servidor: se vuelve a pedir
  Future<void> _verify(BuildContext context, WidgetRef ref) async {
    final done = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const VerifyDniScreen()));
    if (done == true) ref.invalidate(profileProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);

    return Scaffold(
      backgroundColor: _fondo,
      appBar: AppBar(
        backgroundColor: _fondo,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          key: const Key('boton-volver-perfil'),
          tooltip: 'Volver',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Perfil',
          style: TextStyle(fontWeight: FontWeight.w800, color: authText),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                profile.when(
                  data: (user) => _Header(
                    user: user,
                    onVerify: () => _verify(context, ref),
                  ),
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (_, _) => _LoadError(
                    onRetry: () => ref.invalidate(profileProvider),
                  ),
                ),
                const _SectionTitle('SEGURIDAD'),
                _Group(
                  children: [
                    _Row(
                      rowKey: const Key('fila-cambiar-contrasena'),
                      title: 'Cambiar contraseña',
                      onTap: () => Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) => const ChangePasswordScreen(),
                        ),
                      ),
                    ),
                  ],
                ),
                const _SectionTitle('PRIVACIDAD'),
                _Group(
                  children: [
                    _Row(
                      rowKey: const Key('fila-que-guardamos'),
                      title: 'Qué guardamos de ti',
                      onTap: () => _showWhatWeStore(context),
                    ),
                    _Row(
                      rowKey: const Key('fila-borrar-cuenta'),
                      title: 'Borrar mi cuenta',
                      danger: true,
                      onTap: () => Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) => const DeleteAccountScreen(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  height: 52,
                  child: OutlinedButton(
                    key: const Key('boton-cerrar-sesion'),
                    onPressed: () => _signOut(context, ref),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: authError,
                      backgroundColor: Colors.white,
                      side: const BorderSide(color: Color(0xFFFCA5A5)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: const Text('Cerrar sesión'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

void _showWhatWeStore(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => const SafeArea(
      child: Padding(
        key: Key('hoja-que-guardamos'),
        padding: EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Qué guardamos de ti',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 16),
            _InfoBlock(
              icon: Icons.check_circle_outline,
              color: _verde,
              title: 'Sí guardamos',
              text:
                  'Tu alias, una versión cifrada de tu contraseña (nunca tu '
                  'contraseña), la fecha en que aceptaste la política de '
                  'privacidad y los días en que iniciaste sesión, sin la hora.',
            ),
            SizedBox(height: 14),
            _InfoBlock(
              icon: Icons.block,
              color: authError,
              title: 'No guardamos',
              text:
                  'Tu nombre, tu correo, tu teléfono ni tu IP. Tampoco '
                  'guardamos quién hizo cada reporte: cada uno lleva un código '
                  'distinto que no se puede enlazar con tu cuenta ni con tus '
                  'otros reportes.',
            ),
          ],
        ),
      ),
    ),
  );
}

class _InfoBlock extends StatelessWidget {
  const _InfoBlock({
    required this.icon,
    required this.color,
    required this.title,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(text, style: const TextStyle(color: authMuted)),
            ],
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.user, required this.onVerify});

  final AuthUser user;
  final VoidCallback onVerify;

  @override
  Widget build(BuildContext context) {
    final verified = user.nivel == AuthLevel.verificado;
    final desde = user.desde;
    final cupo = user.cupo;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: _card,
          child: Row(
            children: [
              CircleAvatar(
                key: const Key('perfil-iniciales'),
                radius: 30,
                backgroundColor: const Color(0xFFDBEAFE),
                child: Text(
                  initialsOf(user.alias),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: authBlue,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.alias,
                      key: const Key('perfil-alias'),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: authText,
                      ),
                    ),
                    if (desde != null)
                      Text(
                        'Alias público · desde ${monthYear(desde)}',
                        style: const TextStyle(color: authMuted),
                      ),
                    const SizedBox(height: 6),
                    _LevelBadge(verified: verified),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          key: const Key('perfil-cupo'),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
          decoration: _card,
          child: Row(
            children: [
              const Icon(Icons.edit_note, color: authBlue),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Reportes de hoy',
                  style: TextStyle(fontSize: 16, color: authText),
                ),
              ),
              if (cupo != null)
                Text(
                  '${cupo.usados} de ${cupo.maximo}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: authText,
                  ),
                ),
            ],
          ),
        ),
        if (!verified) ...[
          const SizedBox(height: 12),
          _VerifyCard(onTap: onVerify),
        ],
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 8, 4, 0),
          child: Text(
            'Tu historial es privado: el servidor no guarda qué reportes son '
            'tuyos.',
            style: TextStyle(fontSize: 13, color: authMuted),
          ),
        ),
      ],
    );
  }
}

/// Invita a verificar la cuenta con el DNI (solo si aún no lo está).
class _VerifyCard extends StatelessWidget {
  const _VerifyCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Material + InkWell (y no un Container con decoración encima): así el
    // destello del toque se ve
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: authBorder),
      ),
      child: InkWell(
        key: const Key('perfil-verificar'),
        customBorder: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.verified_user_outlined, color: authBlue),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Verifica tu DNI',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: authText,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Haz más reportes al día. No guardamos tu número.',
                      style: TextStyle(color: authMuted),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: authMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _LevelBadge extends StatelessWidget {
  const _LevelBadge({required this.verified});

  final bool verified;

  @override
  Widget build(BuildContext context) {
    final color = verified ? _verde : _ambar;
    return Container(
      key: const Key('perfil-nivel'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (verified) Icon(Icons.check, size: 14, color: color),
          if (verified) const SizedBox(width: 4),
          Text(
            verified ? 'Cuenta verificada' : 'Cuenta sin verificar',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('aviso-perfil'),
      padding: const EdgeInsets.all(16),
      decoration: _card,
      child: Row(
        children: [
          const Expanded(
            child: Text('No pudimos cargar tu perfil. Revisa tu conexión.'),
          ),
          TextButton(
            key: const Key('reintentar-perfil'),
            onPressed: onRetry,
            child: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
        color: authMuted,
      ),
    ),
  );
}

class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _card,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 16),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.rowKey,
    required this.title,
    required this.onTap,
    this.danger = false,
  });

  final Key rowKey;
  final String title;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: rowKey,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  color: danger ? authError : authText,
                ),
              ),
            ),
            const Icon(Icons.chevron_right, color: authMuted),
          ],
        ),
      ),
    );
  }
}

final _card = BoxDecoration(
  color: Colors.white,
  borderRadius: BorderRadius.circular(16),
  border: Border.all(color: authBorder),
);
