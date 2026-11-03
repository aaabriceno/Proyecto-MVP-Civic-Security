import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// Abre el marcador del teléfono con un número. Es una interfaz para poder
/// reemplazarla por un falso en los tests.
abstract interface class Dialer {
  Future<void> dial(String number);
}

/// Solo abre el marcador con el número escrito: el usuario decide si llama.
/// No pide el permiso CALL_PHONE.
class UrlLauncherDialer implements Dialer {
  @override
  Future<void> dial(String number) async {
    await launchUrl(Uri(scheme: 'tel', path: number));
  }
}

final dialerProvider = Provider<Dialer>((ref) => UrlLauncherDialer());
