import 'dart:async';

import 'package:civic_security/core/realtime/phoenix_channel.dart';
import 'package:civic_security/features/incident/domain/incident.dart';
import 'package:civic_security/features/map/data/incident_stream.dart';

/// Tiempo real falso para tests de la app: el test decide qué llega y cuándo.
class FakeIncidentStream implements IncidentStream {
  final _incidents = StreamController<Incident>.broadcast();
  final _statuses = StreamController<RealtimeStatus>.broadcast();

  RealtimeStatus _status = RealtimeStatus.disconnected;
  int starts = 0;
  int stops = 0;

  @override
  Stream<Incident> get incidents => _incidents.stream;

  @override
  Stream<RealtimeStatus> get statuses => _statuses.stream;

  @override
  RealtimeStatus get status => _status;

  @override
  void start() => starts++;

  @override
  void stop() => stops++;

  @override
  void dispose() {
    unawaited(_incidents.close());
    unawaited(_statuses.close());
  }

  // --- Lo que el test usa para simular el servidor ---

  void emit(Incident incident) => _incidents.add(incident);

  void setStatus(RealtimeStatus status) {
    _status = status;
    _statuses.add(status);
  }
}
