import 'dart:async';
import 'dart:typed_data';

import 'package:civic_security/core/network/api_failure.dart';
import 'package:civic_security/features/incident/data/incident_repository.dart';
import 'package:civic_security/features/incident/domain/incident.dart';
import 'package:civic_security/features/map/presentation/map_incidents_controller.dart';
import 'package:civic_security/features/report/domain/new_incident.dart';
import 'package:civic_security/features/report/presentation/report_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

const _robo = NewIncident(
  tipo: IncidentType.robo,
  descripcion: 'x',
  lat: -16.4,
  lng: -71.5,
);

final _foto = Uint8List.fromList([0xFF, 0xD8, 1, 2, 3, 0xFF, 0xD9]);

(ProviderContainer, ReportFakeRepo) _setup() {
  final repo = ReportFakeRepo();
  final container = ProviderContainer(
    overrides: [incidentRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(container.dispose);
  container.listen(reportControllerProvider, (_, _) {});
  return (container, repo);
}

ReportController _controller(ProviderContainer c) =>
    c.read(reportControllerProvider.notifier);

void main() {
  test(
    'sin foto no se sube nada y el estado de la foto es "ninguna"',
    () async {
      final (c, repo) = _setup();

      await _controller(c).submit(_robo);

      expect(repo.uploads, isEmpty);
      expect(c.read(reportControllerProvider).photo, PhotoStatus.none);
    },
  );

  test(
    'con foto: primero crea el reporte y luego sube la foto a ese reporte',
    () async {
      final (c, repo) = _setup();

      await _controller(c).submit(_robo, photo: _foto);

      final created = c.read(reportControllerProvider).created!;
      expect(repo.sent, hasLength(1));
      expect(repo.uploads, [(created.id, _foto)]);
    },
  );

  test(
    'si todo sale bien, el reporte queda con su foto, también en el mapa',
    () async {
      final (c, _) = _setup();

      await _controller(c).submit(_robo, photo: _foto);

      final s = c.read(reportControllerProvider);
      expect(s.photo, PhotoStatus.uploaded);
      expect(s.created!.tieneFoto, isTrue);
      expect(s.photoFailure, isNull);
      expect(s.failure, isNull);
      expect(c.read(mapIncidentsProvider).incidents.single.tieneFoto, isTrue);
    },
  );

  test(
    'mientras sube, el estado es "subiendo" y el reporte ya está creado',
    () async {
      final (c, repo) = _setup();
      repo.photoGate = Completer<void>();

      final envio = _controller(c).submit(_robo, photo: _foto);
      await Future<void>.delayed(Duration.zero);

      final s = c.read(reportControllerProvider);
      expect(
        s.created,
        isNotNull,
        reason: 'la pantalla de "enviado" ya puede abrirse',
      );
      expect(s.photo, PhotoStatus.uploading);
      expect(c.read(mapIncidentsProvider).incidents.single.tieneFoto, isFalse);

      repo.photoGate!.complete();
      await envio;
      expect(c.read(reportControllerProvider).photo, PhotoStatus.uploaded);
    },
  );

  group('si la foto falla, el reporte NO se pierde', () {
    test('queda creado, sin foto, con el error de la foto aparte', () async {
      final (c, repo) = _setup();
      repo.photoFailure = const ApiFailure.network();

      await _controller(c).submit(_robo, photo: _foto);

      final s = c.read(reportControllerProvider);
      expect(s.created, isNotNull);
      expect(s.created!.tieneFoto, isFalse);
      expect(s.photo, PhotoStatus.failed);
      expect(s.photoFailure!.code, 'network');
      expect(s.failure, isNull, reason: 'el reporte en sí salió bien');
      expect(c.read(mapIncidentsProvider).incidents.single.tieneFoto, isFalse);
    });

    test(
      'reintentar sube la misma foto sin volver a crear el reporte',
      () async {
        final (c, repo) = _setup();
        repo.photoFailure = const ApiFailure.network();
        await _controller(c).submit(_robo, photo: _foto);

        repo.photoFailure = null;
        await _controller(c).retryPhoto();

        final s = c.read(reportControllerProvider);
        expect(s.photo, PhotoStatus.uploaded);
        expect(s.created!.tieneFoto, isTrue);
        expect(s.photoFailure, isNull);
        expect(repo.sent, hasLength(1), reason: 'no se crea otro reporte');
        expect(repo.uploads, hasLength(2));
        expect(repo.uploads.last, (s.created!.id, _foto));
      },
    );

    test('un reintento que falla de nuevo vuelve a "falló"', () async {
      final (c, repo) = _setup();
      repo.photoFailure = const ApiFailure.network();
      await _controller(c).submit(_robo, photo: _foto);

      await _controller(c).retryPhoto();

      expect(c.read(reportControllerProvider).photo, PhotoStatus.failed);
    });

    test(
      'si el servidor dice que ya tenía foto (se perdió la respuesta), cuenta como subida',
      () async {
        final (c, repo) = _setup();
        repo.photoFailure = const ApiFailure.network();
        await _controller(c).submit(_robo, photo: _foto);

        repo.photoFailure = const ApiFailure(
          code: 'photo_exists',
          message: 'x',
        );
        await _controller(c).retryPhoto();

        final s = c.read(reportControllerProvider);
        expect(s.photo, PhotoStatus.uploaded);
        expect(s.created!.tieneFoto, isTrue);
        expect(c.read(mapIncidentsProvider).incidents.single.tieneFoto, isTrue);
      },
    );

    test('un error inesperado también queda como "falló"', () async {
      final (c, repo) = _setup();
      repo.photoFailure = const ApiFailure.unexpected();

      await _controller(c).submit(_robo, photo: _foto);

      expect(c.read(reportControllerProvider).photo, PhotoStatus.failed);
    });
  });

  group('retryPhoto no hace nada fuera de lugar', () {
    test('si no hay foto', () async {
      final (c, repo) = _setup();
      await _controller(c).submit(_robo);

      await _controller(c).retryPhoto();

      expect(repo.uploads, isEmpty);
      expect(c.read(reportControllerProvider).photo, PhotoStatus.none);
    });

    test('si ya se subió', () async {
      final (c, repo) = _setup();
      await _controller(c).submit(_robo, photo: _foto);

      await _controller(c).retryPhoto();

      expect(repo.uploads, hasLength(1));
    });

    test('si todavía está subiendo (doble toque)', () async {
      final (c, repo) = _setup();
      repo.photoFailure = const ApiFailure.network();
      await _controller(c).submit(_robo, photo: _foto);
      repo
        ..photoFailure = null
        ..photoGate = Completer<void>();

      final uno = _controller(c).retryPhoto();
      await Future<void>.delayed(Duration.zero);
      await _controller(c).retryPhoto();

      expect(
        repo.uploads,
        hasLength(2),
        reason: 'el segundo toque no sube otra vez',
      );
      repo.photoGate!.complete();
      await uno;
    });

    test('si el reporte todavía no se creó', () async {
      final (c, repo) = _setup();

      await _controller(c).retryPhoto();

      expect(repo.uploads, isEmpty);
      expect(repo.sent, isEmpty);
    });
  });

  test('enviar de nuevo algo ya enviado no sube la foto otra vez', () async {
    final (c, repo) = _setup();
    await _controller(c).submit(_robo, photo: _foto);

    await _controller(c).submit(_robo, photo: _foto);

    expect(repo.sent, hasLength(1));
    expect(repo.uploads, hasLength(1));
  });

  test('si el reporte falla, no se intenta subir ninguna foto', () async {
    final (c, repo) = _setup();
    repo.failure = const ApiFailure.network();

    await _controller(c).submit(_robo, photo: _foto);

    expect(repo.uploads, isEmpty);
    expect(c.read(reportControllerProvider).created, isNull);
    expect(c.read(reportControllerProvider).photo, PhotoStatus.none);
  });

  test('reenviar tras un fallo del reporte sí sube la foto', () async {
    final (c, repo) = _setup();
    repo.failure = const ApiFailure.network();
    await _controller(c).submit(_robo, photo: _foto);

    repo.failure = null;
    await _controller(c).submit(_robo, photo: _foto);

    expect(repo.uploads, hasLength(1));
    expect(c.read(reportControllerProvider).photo, PhotoStatus.uploaded);
  });
}
