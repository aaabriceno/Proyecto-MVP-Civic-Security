import 'package:flutter_driver/flutter_driver.dart' as driver;
import 'package:integration_test/integration_test_driver.dart';

/// Recibe la línea de tiempo que graba `integration_test/map_perf_test.dart` y
/// la guarda en `build/<escenario>.timeline_summary.json` (resumen con
/// percentiles) y `build/<escenario>.timeline.json` (para abrir en DevTools).
Future<void> main() {
  return integrationDriver(
    responseDataCallback: (data) async {
      if (data == null) return;
      for (final entry in data.entries) {
        final timeline = driver.Timeline.fromJson(
          entry.value as Map<String, dynamic>,
        );
        await driver.TimelineSummary.summarize(timeline).writeTimelineToFile(
          entry.key,
          destinationDirectory: 'build',
          pretty: true,
          includeSummary: true,
        );
      }
    },
  );
}
