import 'dart:async';

import 'package:civic_security/core/network/api_failure.dart';
import 'package:civic_security/features/auth/domain/auth_models.dart';
import 'package:civic_security/features/auth/presentation/auth_controller.dart';
import 'package:civic_security/features/incident/data/incident_repository.dart';
import 'package:civic_security/features/incident/domain/incident.dart';
import 'package:civic_security/features/map/presentation/incident_detail.dart';
import 'package:civic_security/features/map/presentation/map_incidents_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import '../report/fakes.dart';

const _aqui = LatLng(-16.4, -71.53);

const _cuenta = AuthUser(
  id: '89e95dd3-b844-4c68-8186-c778448e407a',
  alias: 'Halcon-Misti-482',
  nivel: AuthLevel.verificado,
);

class _FakeAuth extends AuthController {
  _FakeAuth(this._initial);

  final AuthState _initial;

  @override
  AuthState build() => _initial;
}

Incident _incident({
  IncidentStatus estado = IncidentStatus.sinVerificar,
  int confirmaciones = 0,
  int falsos = 0,
}) => Incident(
  id: 'inc-1',
  tipo: IncidentType.robo,
  descripcion: 'Me robaron el celular',
  position: _aqui,
  estado: estado,
  creadoEn: DateTime.now().toUtc(),
  confirmaciones: confirmaciones,
  falsos: falsos,
);

class _Escena {
  _Escena(this.tester, this.repo, this.container);

  final WidgetTester tester;
  final ReportFakeRepo repo;
  final ProviderContainer container;
}

Future<_Escena> _abrir(
  WidgetTester tester,
  Incident incident, {
  AuthState auth = const AuthState.signedIn(_cuenta),
  LatLng? userPosition = _aqui,
  ReportFakeRepo? repo,
  Size size = const Size(1000, 2400),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final fake = repo ?? ReportFakeRepo();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        incidentRepositoryProvider.overrideWithValue(fake),
        authControllerProvider.overrideWith(() => _FakeAuth(auth)),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showIncidentDetail(
              context,
              incident,
              userPosition: userPosition,
            ),
            child: const Text('abrir'),
          ),
        ),
      ),
    ),
  );
  final container = ProviderScope.containerOf(
    tester.element(find.byType(MaterialApp)),
  );
  // El reporte ya está en el mapa, como cuando se toca un pin
  container.read(mapIncidentsProvider.notifier).upsert(incident);

  await tester.tap(find.text('abrir'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  return _Escena(tester, fake, container);
}

Finder get _confirmo => find.byKey(const Key('votar-confirmo'));
Finder get _falso => find.byKey(const Key('votar-falso'));

void main() {
  group('quién ve los botones', () {
    testWidgets('con sesión y sin verificar el reporte: los dos botones', (
      tester,
    ) async {
      await _abrir(tester, _incident());

      expect(_confirmo, findsOneWidget);
      expect(_falso, findsOneWidget);
      expect(find.text('Lo confirmo'), findsOneWidget);
      expect(find.text('Es falso'), findsOneWidget);
    });

    testWidgets('sin sesión: pide iniciar sesión y no hay botones', (
      tester,
    ) async {
      await _abrir(tester, _incident(), auth: const AuthState.signedOut());

      expect(_confirmo, findsNothing);
      expect(_falso, findsNothing);
      expect(find.textContaining('Inicia sesión'), findsOneWidget);
    });

    testWidgets('un reporte verificado ya no recibe votos', (tester) async {
      await _abrir(
        tester,
        _incident(estado: IncidentStatus.verificado, confirmaciones: 3),
      );

      expect(_confirmo, findsNothing);
      expect(_falso, findsNothing);
      expect(find.textContaining('La comunidad verificó'), findsOneWidget);
    });

    testWidgets('un reporte descartado ya no recibe votos', (tester) async {
      await _abrir(
        tester,
        _incident(estado: IncidentStatus.descartado, falsos: 3),
      );

      expect(_confirmo, findsNothing);
      expect(find.textContaining('La comunidad descartó'), findsOneWidget);
    });

    testWidgets('muestra cuántos confirman y cuántos dicen que es falso', (
      tester,
    ) async {
      await _abrir(tester, _incident(confirmaciones: 2, falsos: 1));

      expect(find.byKey(const Key('conteo-confirmaciones')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('conteo-confirmaciones')),
          matching: find.text('2'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('conteo-falsos')),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
    });
  });

  group('pantallas angostas', () {
    for (final ancho in [320.0, 360.0]) {
      testWidgets('a $ancho px de ancho nada se desborda', (tester) async {
        await _abrir(
          tester,
          _incident(confirmaciones: 12, falsos: 10),
          size: Size(ancho, 800),
        );

        expect(tester.takeException(), isNull);
        expect(_confirmo, findsOneWidget);
        expect(_falso, findsOneWidget);
      });
    }
  });

  group('votar', () {
    testWidgets('Lo confirmo envía el voto desde donde está la persona', (
      tester,
    ) async {
      final repo = ReportFakeRepo()..voteResult = _incident(confirmaciones: 1);
      await _abrir(tester, _incident(), repo: repo);

      await tester.tap(_confirmo);
      await tester.pump();
      await tester.pump();

      expect(repo.votes, [('inc-1', VoteValue.confirmo, _aqui)]);
    });

    testWidgets('Es falso envía el voto contrario', (tester) async {
      final repo = ReportFakeRepo()..voteResult = _incident(falsos: 1);
      await _abrir(tester, _incident(), repo: repo);

      await tester.tap(_falso);
      await tester.pump();
      await tester.pump();

      expect(repo.votes.single.$2, VoteValue.falso);
    });

    testWidgets(
      'al votar agradece, quita los botones y actualiza los conteos',
      (tester) async {
        final repo = ReportFakeRepo()
          ..voteResult = _incident(confirmaciones: 1);
        await _abrir(tester, _incident(), repo: repo);

        await tester.tap(_confirmo);
        await tester.pump();
        await tester.pump();

        expect(find.byKey(const Key('voto-registrado')), findsOneWidget);
        expect(_confirmo, findsNothing);
        expect(_falso, findsNothing);
        expect(
          find.descendant(
            of: find.byKey(const Key('conteo-confirmaciones')),
            matching: find.text('1'),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('el reporte actualizado también llega al mapa', (tester) async {
      final repo = ReportFakeRepo()
        ..voteResult = _incident(
          estado: IncidentStatus.verificado,
          confirmaciones: 3,
        );
      final escena = await _abrir(tester, _incident(), repo: repo);

      await tester.tap(_confirmo);
      await tester.pump();
      await tester.pump();

      final enMapa = escena.container
          .read(mapIncidentsProvider)
          .incidents
          .single;
      expect(enMapa.estado, IncidentStatus.verificado);
      expect(enMapa.confirmaciones, 3);
      // Y el detalle ya cuenta que la comunidad lo verificó
      expect(find.textContaining('La comunidad verificó'), findsOneWidget);
    });

    testWidgets('mientras se envía no se puede votar otra vez', (tester) async {
      final repo = ReportFakeRepo()
        ..voteResult = _incident(confirmaciones: 1)
        ..voteGate = Completer<void>();
      await _abrir(tester, _incident(), repo: repo);

      // Dos toques en el mismo cuadro: la pantalla aún no se redibujó con los
      // botones apagados, así que quien lo impide es el propio controlador
      await tester.tap(_confirmo);
      await tester.tap(_falso);
      await tester.pump();

      expect(repo.votes, hasLength(1));
      expect(find.byKey(const Key('votando')), findsOneWidget);

      // Y ya redibujada, los botones no responden
      await tester.tap(_falso, warnIfMissed: false);
      await tester.tap(_confirmo, warnIfMissed: false);
      await tester.pump();
      expect(repo.votes, hasLength(1));

      repo.voteGate!.complete();
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('votando')), findsNothing);
    });

    testWidgets('sin ubicación no se vota y se explica por qué', (
      tester,
    ) async {
      final repo = ReportFakeRepo();
      await _abrir(tester, _incident(), userPosition: null, repo: repo);

      await tester.tap(_confirmo);
      await tester.pump();

      expect(repo.votes, isEmpty);
      expect(find.textContaining('ubicación'), findsWidgets);
      expect(find.byKey(const Key('voto-error')), findsOneWidget);
    });
  });

  group('cuando el voto falla', () {
    const casos = {
      'not_verified': 'Verifica tu cuenta con el DNI',
      'own_report': 'No puedes votar tu propio reporte',
      'too_far': 'cerca del lugar',
      'voting_closed': 'ya no recibe votos',
      'unauthorized': 'Inicia sesión',
      'network': 'Revisa tu conexión',
      'algo_raro': 'No pudimos registrar tu voto',
    };

    for (final MapEntry(key: code, value: texto) in casos.entries) {
      testWidgets('$code: lo dice con palabras propias', (tester) async {
        final repo = ReportFakeRepo()
          ..voteFailure = ApiFailure(
            code: code,
            message: 'TEXTO CRUDO DEL SERVIDOR',
          );
        await _abrir(tester, _incident(), repo: repo);

        await tester.tap(_confirmo);
        await tester.pump();
        await tester.pump();

        expect(find.byKey(const Key('voto-error')), findsOneWidget);
        expect(find.textContaining(texto), findsOneWidget);
        expect(find.textContaining('TEXTO CRUDO'), findsNothing);
      });
    }

    testWidgets('después de un error se puede volver a intentar', (
      tester,
    ) async {
      final repo = ReportFakeRepo()
        ..voteFailure = const ApiFailure.network()
        ..voteResult = _incident(confirmaciones: 1);
      await _abrir(tester, _incident(), repo: repo);

      await tester.tap(_confirmo);
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('voto-error')), findsOneWidget);

      repo.voteFailure = null;
      await tester.tap(_confirmo);
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('voto-error')), findsNothing);
      expect(find.byKey(const Key('voto-registrado')), findsOneWidget);
      expect(repo.votes, hasLength(2));
    });

    testWidgets('already_voted: dice que ya votó y quita los botones', (
      tester,
    ) async {
      final repo = ReportFakeRepo()
        ..voteFailure = const ApiFailure(code: 'already_voted', message: 'x');
      await _abrir(tester, _incident(), repo: repo);

      await tester.tap(_confirmo);
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('Ya votaste'), findsOneWidget);
      expect(_confirmo, findsNothing);
    });
  });

  group('en vivo', () {
    testWidgets(
      'si otra persona vota mientras el detalle está abierto, se ve',
      (tester) async {
        final escena = await _abrir(tester, _incident());

        escena.container
            .read(mapIncidentsProvider.notifier)
            .upsert(_incident(confirmaciones: 2, falsos: 1));
        await tester.pump();

        expect(
          find.descendant(
            of: find.byKey(const Key('conteo-confirmaciones')),
            matching: find.text('2'),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('si otra persona lo verifica, desaparecen los botones', (
      tester,
    ) async {
      final escena = await _abrir(tester, _incident());

      escena.container
          .read(mapIncidentsProvider.notifier)
          .upsert(
            _incident(estado: IncidentStatus.verificado, confirmaciones: 3),
          );
      await tester.pump();

      expect(_confirmo, findsNothing);
      expect(find.textContaining('La comunidad verificó'), findsOneWidget);
    });
  });
}
