import 'dart:async';

import 'package:civic_security/core/network/api_failure.dart';
import 'package:civic_security/features/heat/data/heat_repository.dart';
import 'package:civic_security/features/heat/domain/heat_map.dart';
import 'package:civic_security/features/heat/presentation/heat_controller.dart';
import 'package:civic_security/features/incident/domain/incident.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _bbox = Bbox(
  minLng: -71.75,
  minLat: -16.6,
  maxLng: -71.4,
  maxLat: -16.25,
);
const _otro = Bbox(
  minLng: -71.54,
  minLat: -16.40,
  maxLng: -71.53,
  maxLat: -16.39,
);

HeatMap _map(int max) => HeatMap(cellDeg: 0.02, max: max, cells: const []);

/// Repositorio falso: cada llamada queda pendiente hasta que el test la resuelva.
class _FakeRepo implements HeatRepository {
  final calls = <(Bbox, HeatWindow)>[];
  final pending = <Completer<HeatMap>>[];

  @override
  Future<HeatMap> fetch(Bbox bbox, HeatWindow window) {
    calls.add((bbox, window));
    final c = Completer<HeatMap>();
    pending.add(c);
    return c.future;
  }
}

(ProviderContainer, _FakeRepo) _setup() {
  final repo = _FakeRepo();
  final container = ProviderContainer(
    overrides: [heatRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(container.dispose);
  // autoDispose: un oyente evita que se descarte entre una lectura y otra
  container.listen(heatControllerProvider, (_, _) {});
  return (container, repo);
}

void main() {
  test('empieza en 24 h, vacío y sin cargar', () {
    final (c, _) = _setup();
    final s = c.read(heatControllerProvider);

    expect(s.window, HeatWindow.day);
    expect(s.loading, isFalse);
    expect(s.data, isNull);
    expect(s.failure, isNull);
  });

  test(
    'load pide la zona con la ventana actual y publica el resultado',
    () async {
      final (c, repo) = _setup();

      final future = c.read(heatControllerProvider.notifier).load(_bbox);
      expect(c.read(heatControllerProvider).loading, isTrue);
      expect(repo.calls, [(_bbox, HeatWindow.day)]);

      repo.pending.single.complete(_map(5));
      await future;

      final s = c.read(heatControllerProvider);
      expect(s.loading, isFalse);
      expect(s.data!.max, 5);
      expect(s.failure, isNull);
    },
  );

  test(
    'cambiar de ventana repite la última zona con la ventana nueva',
    () async {
      final (c, repo) = _setup();
      final notifier = c.read(heatControllerProvider.notifier);
      final first = notifier.load(_bbox);
      repo.pending[0].complete(_map(5));
      await first;

      final future = notifier.setWindow(HeatWindow.week);
      expect(c.read(heatControllerProvider).window, HeatWindow.week);
      repo.pending[1].complete(_map(9));
      await future;

      expect(repo.calls.last, (_bbox, HeatWindow.week));
      expect(c.read(heatControllerProvider).data!.max, 9);
    },
  );

  test(
    'elegir la ventana que ya está elegida no vuelve a pedir nada',
    () async {
      final (c, repo) = _setup();
      final notifier = c.read(heatControllerProvider.notifier);
      final first = notifier.load(_bbox);
      repo.pending[0].complete(_map(5));
      await first;

      await notifier.setWindow(HeatWindow.day);

      expect(repo.calls, hasLength(1));
    },
  );

  test(
    'cambiar de ventana antes de haber cargado una zona solo la guarda',
    () async {
      final (c, repo) = _setup();

      await c.read(heatControllerProvider.notifier).setWindow(HeatWindow.hour);

      expect(c.read(heatControllerProvider).window, HeatWindow.hour);
      expect(repo.calls, isEmpty);
    },
  );

  test('una respuesta que llega tarde no pisa a la más reciente', () async {
    final (c, repo) = _setup();
    final notifier = c.read(heatControllerProvider.notifier);

    final lenta = notifier.load(_bbox);
    final rapida = notifier.load(_otro);
    repo.pending[1].complete(_map(2));
    await rapida;
    repo.pending[0].complete(_map(99));
    await lenta;

    expect(c.read(heatControllerProvider).data!.max, 2);
  });

  test('un fallo conserva lo que ya se veía y deja el error', () async {
    final (c, repo) = _setup();
    final notifier = c.read(heatControllerProvider.notifier);
    final first = notifier.load(_bbox);
    repo.pending[0].complete(_map(5));
    await first;

    final second = notifier.load(_otro);
    repo.pending[1].completeError(const ApiFailure.network());
    await second;

    final s = c.read(heatControllerProvider);
    expect(s.loading, isFalse);
    expect(s.data!.max, 5, reason: 'se conserva el mapa anterior');
    expect(s.failure!.code, 'network');
  });

  test('un error que no es de la API se muestra como inesperado', () async {
    final (c, repo) = _setup();

    final future = c.read(heatControllerProvider.notifier).load(_bbox);
    repo.pending[0].completeError(StateError('algo raro'));
    await future;

    expect(c.read(heatControllerProvider).failure!.code, 'unexpected');
  });

  test('una carga correcta borra el error anterior', () async {
    final (c, repo) = _setup();
    final notifier = c.read(heatControllerProvider.notifier);
    final fallida = notifier.load(_bbox);
    repo.pending[0].completeError(const ApiFailure.network());
    await fallida;

    final buena = notifier.load(_bbox);
    repo.pending[1].complete(_map(1));
    await buena;

    expect(c.read(heatControllerProvider).failure, isNull);
  });

  test('retry repite la última zona', () async {
    final (c, repo) = _setup();
    final notifier = c.read(heatControllerProvider.notifier);
    final fallida = notifier.load(_otro);
    repo.pending[0].completeError(const ApiFailure.network());
    await fallida;

    final retry = notifier.retry();
    repo.pending[1].complete(_map(3));
    await retry;

    expect(repo.calls.last, (_otro, HeatWindow.day));
    expect(c.read(heatControllerProvider).data!.max, 3);
  });

  test(
    'si se cierra la pantalla mientras carga, no falla al llegar la respuesta',
    () async {
      final repo = _FakeRepo();
      final container = ProviderContainer(
        overrides: [heatRepositoryProvider.overrideWithValue(repo)],
      );
      final sub = container.listen(heatControllerProvider, (_, _) {});
      final future = container
          .read(heatControllerProvider.notifier)
          .load(_bbox);

      sub.close();
      container.dispose();
      repo.pending.single.complete(_map(1));

      await expectLater(future, completes);
    },
  );
}
