/// Dirección de la API. Se cambia al compilar, sin tocar el código:
///
///     flutter run --dart-define=API_URL=http://10.0.2.2:4000
///
/// 10.0.2.2 es la laptop vista desde el emulador de Android.
const String apiUrl = String.fromEnvironment(
  'API_URL',
  defaultValue: 'http://10.0.2.2:4000',
);
