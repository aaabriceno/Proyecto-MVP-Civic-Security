import 'package:civic_security/core/storage/token_store.dart';
import 'package:civic_security/features/auth/data/auth_repository.dart';
import 'package:civic_security/features/auth/data/session_manager.dart';
import 'package:civic_security/features/auth/domain/auth_models.dart';
import 'package:civic_security/features/auth/presentation/auth_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../auth/fakes.dart';

/// Una cuenta sin verificar con 1 de 3 reportes gastados, creada en septiembre.
final profileUser = AuthUser(
  id: '89e95dd3-b844-4c68-8186-c778448e407a',
  alias: 'Halcon-Misti-482',
  nivel: AuthLevel.invitado,
  desde: DateTime(2026, 9),
  cupo: const ReportQuota(usados: 1, maximo: 3),
);

/// Sesión de mentira: el estado que se indique y un contador de cierres.
class FakeAuth extends AuthController {
  FakeAuth(this._initial);

  final AuthState _initial;
  int logouts = 0;

  @override
  AuthState build() => _initial;

  @override
  Future<void> logout() async {
    logouts++;
    state = const AuthState.signedOut();
  }
}

class Harness {
  Harness(this.container, this.repo, this.store, this.auth);

  final ProviderContainer container;
  final FakeAuthRepository repo;
  final InMemoryTokenStore store;
  final FakeAuth auth;
}

/// Abre [child] desde un botón, con la sesión iniciada y las cuentas conectadas
/// a los falsos, en una pantalla del tamaño de una tablet.
Future<Harness> pumpProfile(
  WidgetTester tester,
  Widget child, {
  FakeAuthRepository? repo,
  AuthUser? user,

  /// `false` si la pantalla tiene una animación infinita (un indicador de
  /// carga): `pumpAndSettle` no terminaría nunca.
  bool settle = true,
}) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final fakeRepo =
      repo ??
      (FakeAuthRepository()
        ..onMe = ((_) async => user ?? profileUser)
        ..onLogout = ((_) async {}));
  final store = InMemoryTokenStore();
  final auth = FakeAuth(AuthState.signedIn(user ?? profileUser));

  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(fakeRepo),
      tokenStoreProvider.overrideWithValue(store),
      authControllerProvider.overrideWith(() => auth),
    ],
  );
  addTearDown(container.dispose);
  await container
      .read(sessionManagerProvider)
      .start(tokens('access-1', 'refresh-1'));

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(
                context,
              ).push<void>(MaterialPageRoute(builder: (_) => child)),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }
  return Harness(container, fakeRepo, store, auth);
}
