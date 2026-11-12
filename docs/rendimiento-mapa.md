# Rendimiento del mapa — medición en tablet

**Fecha:** 2026-11-11 · **Dispositivo:** Lenovo TB350XU (Android, pantalla 1200×2000, modo de 60 Hz) · **Modo:** `profile` (el que se parece a la app real; el modo depuración es entre 3 y 10 veces más lento y no sirve para medir).

## Por qué se midió

En la prueba del 5 de noviembre el mapa se sentía lento. Esa prueba fue en modo depuración, así que no decía nada sobre la app real. Esta medición responde con números si el mapa es fluido y cuántos pines aguanta.

## Cómo se mide

Prueba automática dentro de Flutter (`integration_test`), que arrastra el mapa de ida y vuelta 6 veces y registra cuánto tarda **cada cuadro**. Mide por separado:

- **Interfaz** (hilo de UI): construir widgets, calcular posiciones y registrar qué dibujar.
- **Dibujo** (hilo de raster): pintar con la GPU.

A 60 Hz, cada cuadro dispone de **16,6 ms**. Si cualquiera de los dos hilos tarda más, se pierde un cuadro y se nota.

Los incidentes son sintéticos y siempre los mismos (semilla fija, agrupados alrededor del centro de Arequipa, un tercio de cada estado) para que la medición sea repetible y no dependa del backend. Las teselas del mapa sí vienen de internet. El primer par de arrastres se descarta (descarga teselas y compila shaders).

```bash
cd app
flutter drive --no-dds \
  --driver=test_driver/perf_driver.dart \
  --target=integration_test/map_perf_test.dart \
  --profile -d <id del dispositivo>
# Resultados: app/build/<escenario>.timeline_summary.json
```

Detalles que costó descubrir:

- Hace falta `--no-dds`; sin eso la app no alcanza el servicio de VM y falla.
- El registro de eventos de la VM tiene un tope. Con todos los flujos activos y muchos pines se llena en medio segundo y descarta casi todos los cuadros (salían 17 en lugar de 160). Por eso el test registra solo `Dart` y `Embedder`.
- Medir desde fuera, con `adb input swipe` y los cuadros que presenta Android, **no sirvió**: daba unos 30 cuadros por segundo incluso sin pines, es decir, medía la cadencia de los toques inyectados y no la velocidad de dibujo.

## Resultados

Promedios por cuadro en ms; entre paréntesis, el percentil 99. «Cuadros» es cuántos se produjeron en la misma ventana de tiempo (más es más fluido).

| Pines a la vista | Interfaz antes → después | Dibujo antes → después | Cuadros antes → después |
|---|---|---|---|
| 0 (solo teselas) | 1,9 | 3,0 | 300 |
| 80 | 5,2 → 6,1 (8,6 → 12,4) | 8,4 → **5,6** (11,4 → 8,7) | 160 → **259** |
| 300 | 16,3 → 18,7 | 33,1 → **11,8** | 64 → **175** |
| 600 | 35,4 → 39,2 | 52,6 → **21,8** | 35 → **130** |

## Qué se cambió y qué no

- **Cambiado:** el pin descartado ya no usa `Opacity`. Cada `Opacity` parcial obliga a la GPU a dibujar el pin en una capa aparte y era la mitad del costo de dibujo. Ahora el descartado se ve apagado con un color sólido más claro (`IncidentPin`).
- **Probado y descartado** (no mejoraba, así que se revirtió): reemplazar la sombra con desenfoque por una plana, y envolver cada pin en un `RepaintBoundary`. Las dos dieron mejoras dentro del ruido (≤ 9 %).

## Conclusión

- Con **80 pines** (lo que hay hoy) el mapa es fluido: ningún cuadro pasa de 16,6 ms en ninguno de los dos hilos.
- El límite actual está en el **hilo de interfaz**, a unos **0,06 ms por pin**: se pasa de 16,6 ms alrededor de los **250 pines** visibles al mismo tiempo. Con pines más agrupados o más lejos el costo es el mismo, porque todos se dibujan aunque se tapen entre sí.
- Para el piloto (hasta 50 alumnos) no hace falta más. **Antes de superar ~200 pines visibles hay que agrupar pines por zona** cuando el mapa está alejado (un solo número en lugar de cientos de pines superpuestos, que además son ilegibles). Queda como mejora pendiente con este umbral.
- Si la pantalla funcionara a 120 Hz, el presupuesto baja a 8,3 ms por cuadro y el límite también.
