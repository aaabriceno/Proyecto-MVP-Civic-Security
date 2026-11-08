import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/env.dart';
import '../../../core/network/api_client.dart';
import '../../../core/realtime/phoenix_channel.dart';
import '../../incident/domain/incident.dart';

/// Tópico del backend que anuncia los reportes nuevos de Arequipa.
const mapTopic = 'mapa:arequipa';

/// Reportes nuevos en tiempo real. Es una interfaz para poder reemplazarla por
/// una falsa en los tests.
abstract interface class IncidentStream {
  /// Cada reporte nuevo que publica el servidor.
  Stream<Incident> get incidents;

  Stream<RealtimeStatus> get statuses;
  RealtimeStatus get status;

  /// Empieza a escuchar (y a reconectar solo si se cae).
  void start();

  /// Deja de escuchar, por ejemplo cuando la app pasa a segundo plano.
  void stop();

  void dispose();
}

/// Implementación real: escucha `incidente_nuevo` en el canal de Phoenix.
class PhoenixIncidentStream implements IncidentStream {
  PhoenixIncidentStream(this._channel);

  final PhoenixChannel _channel;

  @override
  Stream<Incident> get incidents =>
      _channel.events.where((e) => e.event == 'incidente_nuevo').expand(_parse);

  /// Un mensaje que no se entiende se descarta: ni rompe el flujo ni cae la
  /// conexión (un servidor más nuevo que la app puede mandar tipos nuevos).
  Iterable<Incident> _parse(PhoenixEvent event) {
    try {
      final incident = Incident.tryFromJson(event.payload);
      return incident == null ? const [] : [incident];
    } on FormatException {
      return const [];
    }
  }

  @override
  Stream<RealtimeStatus> get statuses => _channel.statuses;

  @override
  RealtimeStatus get status => _channel.status;

  @override
  void start() => _channel.connect();

  @override
  void stop() => _channel.disconnect();

  @override
  void dispose() => _channel.dispose();
}

final incidentStreamProvider = Provider<IncidentStream>((ref) {
  // Mismo control que la API REST: en producción solo https, y por tanto wss
  validateApiUrl(apiUrl, release: kReleaseMode);
  final stream = PhoenixIncidentStream(
    PhoenixChannel(url: realtimeUrl(apiUrl), topic: mapTopic),
  );
  ref.onDispose(stream.dispose);
  return stream;
});
