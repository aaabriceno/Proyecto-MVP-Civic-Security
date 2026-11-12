# Civic Security: app

App móvil en **Flutter** (Android primero): mapa en vivo, reporte anónimo y cuentas.

Para levantar el servidor y correr la app en una tablet o teléfono, sigue la
**[guía para ejecutar en local](../docs/guia-ejecucion-local.md)**.

## Comandos más usados

```bash
flutter pub get                                                  # dependencias
flutter run -d <id> --dart-define=API_URL=http://127.0.0.1:4000  # corre en el dispositivo
flutter test                                                     # pruebas
flutter analyze                                                  # análisis estático
dart format lib test                                             # formato
```

`<id>` es el que muestra `flutter devices`. La dirección del servidor (`API_URL`)
se fija al compilar; ver la guía para el cable USB y para el Wi-Fi.

La medición de rendimiento del mapa en un dispositivo real está en
[rendimiento-mapa.md](../docs/rendimiento-mapa.md).
