import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_failure.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/data/session_manager.dart';
import '../../auth/domain/auth_models.dart';

/// Lo que se puede hacer con la propia cuenta: ver el perfil, cambiar la
/// contraseña y borrarla. Une el repositorio (que habla con el servidor) con la
/// sesión (que sabe con qué token hablar y qué guardar).
///
/// Todo fallo se lanza como [ApiFailure].
class AccountService {
  AccountService({required this._repository, required this._session});

  final AuthRepository _repository;
  final SessionManager _session;

  static const _sinSesion = ApiFailure(
    code: 'unauthorized',
    message: 'Necesitas iniciar sesión',
  );

  /// El perfil de la cuenta: alias, nivel, desde cuándo y cupo del día.
  Future<AuthUser> me() async => _repository.me(await _token());

  /// Cambia la contraseña. El servidor cierra TODAS las demás sesiones y da un
  /// refresh token nuevo; se guarda **antes** de volver, porque el que se tenía
  /// ya no sirve y, si se perdiera, habría que volver a iniciar sesión.
  Future<AuthUser> changePassword({
    required String current,
    required String next,
  }) async {
    final session = await _repository.changePassword(
      accessToken: await _token(),
      current: current,
      next: next,
    );
    await _session.start(session.tokens);
    return session.user;
  }

  /// Borra la cuenta en el servidor. Cerrar la sesión local es de quien llama
  /// (`AuthController.logout`), que además deja la app en la pantalla de entrada.
  Future<void> deleteAccount({required String password}) async => _repository
      .deleteAccount(accessToken: await _token(), password: password);

  Future<String> _token() async {
    final token = await _session.validAccessToken();
    if (token == null) throw _sinSesion;
    return token;
  }
}

final accountServiceProvider = Provider<AccountService>(
  (ref) => AccountService(
    repository: ref.watch(authRepositoryProvider),
    session: ref.watch(sessionManagerProvider),
  ),
);

/// El perfil de la cuenta, tal como lo ve el servidor ahora mismo. Se vuelve a
/// pedir cada vez que se abre la pantalla del perfil.
///
/// Sin reintento automático (el de Riverpod 3 vuelve a pedirlo solo, en silencio):
/// si falla, la pantalla lo dice y ofrece "Reintentar".
final profileProvider = FutureProvider.autoDispose<AuthUser>(
  (ref) => ref.watch(accountServiceProvider).me(),
  retry: (_, _) => null,
);
