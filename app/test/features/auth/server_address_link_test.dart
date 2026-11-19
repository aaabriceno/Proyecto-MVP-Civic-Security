import 'package:civic_security/app/civic_root.dart';
import 'package:civic_security/core/config/env.dart';
import 'package:civic_security/core/config/server_address.dart';
import 'package:civic_security/core/storage/token_store.dart';
import 'package:civic_security/features/auth/presentation/server_address_link.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAddressStore implements ServerAddressStore {
  String? saved;
  int clears = 0;

  @override
  Future<String?> read() async => saved;

  @override
  Future<void> save(String url) async => saved = url;

  @override
  Future<void> clear() async {
    clears++;
    saved = null;
  }
}

class _FakeTokens implements TokenStore {
  int clears = 0;

  @override
  Future<String?> readRefreshToken() async => null;

  @override
  Future<void> saveRefreshToken(String token) async {}

  @override
  Future<void> clear() async => clears++;
}

class _Escena {
  _Escena(this.store, this.tokens, this.probed);

  final _FakeAddressStore store;
  final _FakeTokens tokens;
  final List<String> probed;
}

Future<_Escena> _abrir(
  WidgetTester tester, {
  String? initial = 'http://192.168.1.7:4000',
  bool healthy = true,
}) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final store = _FakeAddressStore();
  final tokens = _FakeTokens();
  final probed = <String>[];

  await tester.pumpWidget(
    MaterialApp(
      home: CivicRoot(
        initialServerUrl: initial,
        overrides: [
          serverAddressStoreProvider.overrideWithValue(store),
          tokenStoreProvider.overrideWithValue(tokens),
          serverHealthCheckProvider.overrideWithValue((url) async {
            probed.add(url);
            return healthy;
          }),
        ],
        child: const Scaffold(body: Center(child: ServerAddressLink())),
      ),
    ),
  );
  return _Escena(store, tokens, probed);
}

Finder get _campo => find.byKey(const Key('servidor-campo'));

void main() {
  testWidgets('muestra a qué servidor habla la app', (tester) async {
    await _abrir(tester);

    expect(find.textContaining('192.168.1.7:4000'), findsOneWidget);
    expect(find.text('Cambiar'), findsOneWidget);
  });

  testWidgets('sin dirección guardada muestra la de compilación', (
    tester,
  ) async {
    await _abrir(tester, initial: null);

    expect(find.textContaining(Uri.parse(apiUrl).authority), findsOneWidget);
  });

  testWidgets(
    'guardar otra dirección la normaliza, cierra la sesión y reinicia',
    (tester) async {
      final escena = await _abrir(tester);

      await tester.tap(find.byKey(const Key('servidor-prueba')));
      await tester.pumpAndSettle();
      await tester.enterText(_campo, '172.20.10.14');
      await tester.tap(find.byKey(const Key('servidor-guardar')));
      await tester.pumpAndSettle();

      expect(escena.store.saved, 'http://172.20.10.14:4000');
      // Los tokens de un servidor no sirven en otro
      expect(escena.tokens.clears, 1);
      // La app se rearmó con la dirección nueva
      expect(find.textContaining('172.20.10.14:4000'), findsOneWidget);
      expect(find.byKey(const Key('servidor-campo')), findsNothing);
    },
  );

  testWidgets('una dirección inválida se explica y no se guarda', (
    tester,
  ) async {
    final escena = await _abrir(tester);

    await tester.tap(find.byKey(const Key('servidor-prueba')));
    await tester.pumpAndSettle();
    await tester.enterText(_campo, 'hola mundo');
    await tester.tap(find.byKey(const Key('servidor-guardar')));
    await tester.pumpAndSettle();

    expect(find.textContaining('dirección válida'), findsOneWidget);
    expect(escena.store.saved, isNull);
    expect(escena.tokens.clears, 0);
    expect(_campo, findsOneWidget, reason: 'el diálogo sigue abierto');
  });

  testWidgets('guardar la misma dirección no cierra la sesión', (tester) async {
    final escena = await _abrir(tester);

    await tester.tap(find.byKey(const Key('servidor-prueba')));
    await tester.pumpAndSettle();
    await tester.enterText(_campo, '192.168.1.7:4000');
    await tester.tap(find.byKey(const Key('servidor-guardar')));
    await tester.pumpAndSettle();

    expect(escena.tokens.clears, 0);
    expect(find.byKey(const Key('servidor-campo')), findsNothing);
  });

  testWidgets('Probar avisa si el servidor responde', (tester) async {
    final escena = await _abrir(tester);

    await tester.tap(find.byKey(const Key('servidor-prueba')));
    await tester.pumpAndSettle();
    await tester.enterText(_campo, '172.20.10.14');
    await tester.tap(find.byKey(const Key('servidor-probar')));
    await tester.pumpAndSettle();

    expect(escena.probed, ['http://172.20.10.14:4000']);
    expect(find.byKey(const Key('servidor-responde')), findsOneWidget);
    expect(escena.store.saved, isNull, reason: 'probar no guarda');
  });

  testWidgets('Probar avisa si el servidor no responde', (tester) async {
    await _abrir(tester, healthy: false);

    await tester.tap(find.byKey(const Key('servidor-prueba')));
    await tester.pumpAndSettle();
    await tester.enterText(_campo, '172.20.10.14');
    await tester.tap(find.byKey(const Key('servidor-probar')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('servidor-no-responde')), findsOneWidget);
    expect(find.byKey(const Key('servidor-responde')), findsNothing);
  });

  testWidgets('Probar con una dirección inválida no sale a la red', (
    tester,
  ) async {
    final escena = await _abrir(tester);

    await tester.tap(find.byKey(const Key('servidor-prueba')));
    await tester.pumpAndSettle();
    await tester.enterText(_campo, '???');
    await tester.tap(find.byKey(const Key('servidor-probar')));
    await tester.pumpAndSettle();

    expect(escena.probed, isEmpty);
    expect(find.textContaining('dirección válida'), findsOneWidget);
  });

  testWidgets('Restablecer vuelve a la dirección de compilación', (
    tester,
  ) async {
    final escena = await _abrir(tester);

    await tester.tap(find.byKey(const Key('servidor-prueba')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('servidor-restablecer')));
    await tester.pumpAndSettle();

    expect(escena.store.clears, 1);
    expect(escena.tokens.clears, 1);
    expect(find.textContaining(Uri.parse(apiUrl).authority), findsOneWidget);
  });
}
