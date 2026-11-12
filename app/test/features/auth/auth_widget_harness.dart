import 'package:civic_security/core/network/api_failure.dart';
import 'package:civic_security/core/storage/token_store.dart';
import 'package:civic_security/features/auth/data/auth_repository.dart';
import 'package:civic_security/features/auth/domain/auth_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

const testUser = AuthUser(
  id: '89e95dd3-b844-4c68-8186-c778448e407a',
  alias: 'Halcon-Misti-482',
  nivel: AuthLevel.invitado,
);

AuthSession testSession() =>
    AuthSession(user: testUser, tokens: tokens('access-1', 'refresh-1'));

ApiFailure failure(
  String code, {
  Duration? retryAfter,
  Map<String, List<String>> fields = const {},
}) => ApiFailure(
  code: code,
  message: 'texto del servidor',
  retryAfter: retryAfter,
  fields: fields,
);

/// Una contraseña que cumple el mínimo del servidor (12) y es "buena" (16+).
const goodPassword = 'una frase larga y facil';

/// Muestra [child] con las cuentas conectadas a los falsos de los tests, en una
/// pantalla de tamaño de tablet.
Future<ProviderContainer> pumpAuth(
  WidgetTester tester,
  Widget child, {
  FakeAuthRepository? repo,
  InMemoryTokenStore? store,
}) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(
        repo ?? (FakeAuthRepository()..onLogout = (_) async {}),
      ),
      tokenStoreProvider.overrideWithValue(store ?? InMemoryTokenStore()),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: child),
    ),
  );
  return container;
}
