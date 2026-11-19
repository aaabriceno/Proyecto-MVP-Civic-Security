import 'package:civic_security/core/config/server_address.dart';
import 'package:civic_security/features/auth/presentation/server_address_link.dart';
import 'package:civic_security/features/auth/presentation/signed_out_flow.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'auth_widget_harness.dart';

class _Almacen implements ServerAddressStore {
  _Almacen(this.value, {this.fails = false});

  final String? value;
  final bool fails;

  /// Cuántas veces se leyó.
  int reads = 0;

  @override
  Future<String?> read() async {
    reads++;
    if (fails) throw StateError('almacén roto');
    return value;
  }

  @override
  Future<void> save(String url) async {}

  @override
  Future<void> clear() async {}
}

Widget _flow({bool? showServerAddress}) => showServerAddress == null
    ? SignedOutFlow(publicMapBuilder: (_, _) => const SizedBox())
    : SignedOutFlow(
        showServerAddress: showServerAddress,
        publicMapBuilder: (_, _) => const SizedBox(),
      );

void main() {
  group('quién puede cambiar de servidor', () {
    testWidgets('en una versión de prueba, la bienvenida lo permite', (
      tester,
    ) async {
      await pumpAuth(tester, _flow(showServerAddress: true));

      expect(find.byType(ServerAddressLink), findsOneWidget);
    });

    testWidgets('en la versión final, no hay dónde cambiarlo', (tester) async {
      await pumpAuth(tester, _flow(showServerAddress: false));

      expect(find.byType(ServerAddressLink), findsNothing);
      expect(find.text('Comenzar'), findsOneWidget);
    });

    testWidgets('por omisión sigue el modo de la compilación', (tester) async {
      // Los tests corren en modo debug, que no es la versión final
      await pumpAuth(tester, _flow());

      expect(find.byType(ServerAddressLink), findsOneWidget);
    });
  });

  group('loadSavedServer', () {
    test('en una versión de prueba devuelve la dirección guardada', () async {
      final url = await loadSavedServer(
        _Almacen('http://172.20.10.14:4000'),
        release: false,
      );

      expect(url, 'http://172.20.10.14:4000');
    });

    test('la versión final ignora lo guardado y ni lo lee', () async {
      final almacen = _Almacen('http://172.20.10.14:4000');

      final url = await loadSavedServer(almacen, release: true);

      expect(url, isNull);
      expect(almacen.reads, 0);
    });

    test('si el almacén falla, usa la dirección de compilación', () async {
      final url = await loadSavedServer(
        _Almacen(null, fails: true),
        release: false,
      );

      expect(url, isNull);
    });
  });
}
