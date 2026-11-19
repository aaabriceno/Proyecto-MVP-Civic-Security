import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app/civic_root.dart';
import 'core/config/server_address.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final saved = await loadSavedServer(
    SecureServerAddressStore(),
    release: kReleaseMode,
  );
  runApp(CivicRoot(initialServerUrl: saved));
}
