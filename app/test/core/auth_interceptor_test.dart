import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:civic_security/core/network/api_failure.dart';
import 'package:civic_security/core/network/auth_interceptor.dart';
import 'package:civic_security/features/auth/data/session_manager.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/auth/fakes.dart';

/// Servidor falso: cada petición la responde [onFetch], y todas quedan anotadas.
class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this.onFetch);

  final ResponseBody Function(RequestOptions options) onFetch;
  final requests = <RequestOptions>[];

  /// Los `Authorization` que llegaron, en orden (`null` si no venía). Se anotan
  /// al recibir: el objeto de la petición se reutiliza y se modifica al reintentar.
  final authorizations = <String?>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    authorizations.add(options.headers['authorization'] as String?);
    return onFetch(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(int status, Object body, {Map<String, List<String>>? h}) =>
    ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json; charset=utf-8'],
        ...?h,
      },
    );

ResponseBody _ok() => _json(201, {'data': {}});
ResponseBody _noAutorizado() => _json(401, {
  'error': {'code': 'unauthorized', 'message': 'Necesitas iniciar sesión'},
});

void main() {
  late InMemoryTokenStore store;
  late FakeAuthRepository repo;
  late SessionManager session;
  late DateTime clock;

  Dio newDio(_ScriptedAdapter adapter) {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = adapter;
    dio.interceptors.add(
      AuthInterceptor(
        dio: dio,
        accessToken: session.validAccessToken,
        refresh: session.refresh,
      ),
    );
    return dio;
  }

  setUp(() {
    store = InMemoryTokenStore();
    repo = FakeAuthRepository();
    clock = DateTime.utc(2026, 11, 15, 12);
    session = SessionManager(repository: repo, store: store, now: () => clock);
  });

  group('peticiones que necesitan sesión', () {
    test('agregan Authorization: Bearer con el access token vigente', () async {
      await session.start(tokens('access-1', 'refresh-1'));
      final adapter = _ScriptedAdapter((_) => _ok());

      await newDio(
        adapter,
      ).post<Object?>('/v1/incidents', options: conSesion());

      expect(adapter.authorizations, ['Bearer access-1']);
    });

    test('con el access token vencido lo renueva antes de enviar', () async {
      await session.start(tokens('access-1', 'refresh-1'));
      clock = clock.add(const Duration(minutes: 20));
      repo.onRefresh = (_) async => tokens('access-2', 'refresh-2');
      final adapter = _ScriptedAdapter((_) => _ok());

      await newDio(
        adapter,
      ).post<Object?>('/v1/incidents', options: conSesion());

      expect(adapter.authorizations, ['Bearer access-2']);
      expect(repo.refreshCalls, ['refresh-1']);
    });

    test(
      'sin sesión no sale ninguna petición y falla con unauthorized',
      () async {
        final adapter = _ScriptedAdapter((_) => _ok());

        final dio = newDio(adapter);
        final error = await _failure(
          () => dio.post<Object?>('/v1/incidents', options: conSesion()),
        );

        expect(error.code, 'unauthorized');
        expect(adapter.requests, isEmpty);
      },
    );

    test(
      'si no se puede renovar por falta de red, falla con network',
      () async {
        await session.start(tokens('access-1', 'refresh-1'));
        clock = clock.add(const Duration(minutes: 20));
        repo.onRefresh = (_) async => throw const ApiFailure.network();
        final adapter = _ScriptedAdapter((_) => _ok());

        final dio = newDio(adapter);
        final error = await _failure(
          () => dio.post<Object?>('/v1/incidents', options: conSesion()),
        );

        expect(error.code, 'network');
        expect(adapter.requests, isEmpty);
      },
    );

    test('un 401 renueva la sesión y repite la petición UNA vez', () async {
      await session.start(tokens('access-1', 'refresh-1'));
      repo.onRefresh = (_) async => tokens('access-2', 'refresh-2');
      final adapter = _ScriptedAdapter(
        (o) => o.headers['authorization'] == 'Bearer access-2'
            ? _ok()
            : _noAutorizado(),
      );

      final response = await newDio(
        adapter,
      ).post<Object?>('/v1/incidents', options: conSesion());

      expect(response.statusCode, 201);
      expect(adapter.authorizations, ['Bearer access-1', 'Bearer access-2']);
      expect(repo.refreshCalls, ['refresh-1']);
    });

    test('si tras renovar sigue el 401, no reintenta otra vez', () async {
      await session.start(tokens('access-1', 'refresh-1'));
      repo.onRefresh = (_) async => tokens('access-2', 'refresh-2');
      final adapter = _ScriptedAdapter((_) => _noAutorizado());

      final dio = newDio(adapter);
      final error = await _failure(
        () => dio.post<Object?>('/v1/incidents', options: conSesion()),
      );

      expect(error.code, 'unauthorized');
      expect(adapter.requests, hasLength(2));
      expect(repo.refreshCalls, hasLength(1));
    });

    test('un 401 con la sesión ya terminada falla sin reintentar', () async {
      await session.start(tokens('access-1', 'refresh-1'));
      repo.onRefresh = (_) async => throw const ApiFailure(
        code: 'invalid_token',
        message: 'Sesión inválida o vencida',
      );
      final adapter = _ScriptedAdapter((_) => _noAutorizado());

      final dio = newDio(adapter);
      final error = await _failure(
        () => dio.post<Object?>('/v1/incidents', options: conSesion()),
      );

      expect(error.code, 'unauthorized');
      expect(adapter.requests, hasLength(1));
      expect(store.value, isNull, reason: 'la sesión local se borra');
    });

    test('los errores que no son 401 no tocan la sesión', () async {
      await session.start(tokens('access-1', 'refresh-1'));
      final adapter = _ScriptedAdapter(
        (_) => _json(
          429,
          {
            'error': {'code': 'report_quota_exceeded', 'message': 'Cupo'},
          },
          h: {
            'retry-after': ['3600'],
          },
        ),
      );

      final dio = newDio(adapter);
      final error = await _failure(
        () => dio.post<Object?>('/v1/incidents', options: conSesion()),
      );

      expect(error.code, 'report_quota_exceeded');
      expect(error.retryAfter, const Duration(hours: 1));
      expect(repo.refreshCalls, isEmpty);
      expect(adapter.requests, hasLength(1));
    });
  });

  group('peticiones públicas', () {
    test('no llevan Authorization aunque haya sesión', () async {
      await session.start(tokens('access-1', 'refresh-1'));
      final adapter = _ScriptedAdapter((_) => _json(200, {'data': {}}));

      await newDio(adapter).get<Object?>('/v1/map/snapshot');

      expect(adapter.authorizations, [null]);
    });

    test('funcionan sin sesión (el mapa de solo lectura)', () async {
      final adapter = _ScriptedAdapter((_) => _json(200, {'data': {}}));

      final response = await newDio(adapter).get<Object?>('/v1/map/snapshot');

      expect(response.statusCode, 200);
      expect(repo.refreshCalls, isEmpty);
    });

    test('un 401 público no intenta renovar nada', () async {
      await session.start(tokens('access-1', 'refresh-1'));
      final adapter = _ScriptedAdapter((_) => _noAutorizado());

      final dio = newDio(adapter);
      await _failure(() => dio.get<Object?>('/v1/map/snapshot'));

      expect(repo.refreshCalls, isEmpty);
    });
  });
}

/// Corre [action], que debe fallar con un [DioException], y devuelve el error de
/// la API ya traducido, como lo ve el resto de la app.
Future<ApiFailure> _failure(Future<Object?> Function() action) async {
  try {
    await action();
  } on DioException catch (e) {
    return ApiFailure.fromDio(e);
  }
  fail('Debió fallar');
}
