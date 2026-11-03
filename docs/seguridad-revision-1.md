# Revisión de seguridad 1 — Civic Security (backend, app Android, repo)

**Fecha:** 2026-11-03 · **Alcance:** backend Phoenix, canal WebSocket, base de datos local, app Flutter (Android) y repositorio, en el estado del avance 1.
**Método:** revisión de código, herramientas automáticas (Sobelow, `mix deps.audit`, `mix hex.audit`, OSV para `pubspec.lock`) y **ataques reales** contra el servidor antes y después de las correcciones.
**Referencias:** OWASP ASVS 4.0, OWASP API Security Top 10 (2023), OWASP MASVS v2, Ley N.º 29733.

## Resumen

Se encontraron y corrigieron **12 hallazgos** (3 de severidad alta, 6 media y 3 baja). Después de las correcciones: 58 tests en verde, Sobelow y auditorías de dependencias sin hallazgos, y los mismos ataques ya no funcionan. Quedan **riesgos aceptados o pendientes** documentados al final; ninguno es explotable con el alcance actual del avance (sin cuentas ni datos personales).

## Hallazgos corregidos

| # | Hallazgo | Tríada | Severidad | Evidencia antes | Corrección | Referencia |
|---|---|---|---|---|---|---|
| 1 | **Sin límite de solicitudes**: 150 reportes seguidos desde una IP, todos aceptados; 100 lecturas, todas aceptadas | Disponibilidad, Integridad | Alta | 150 × `201` | Rate limiting en memoria (Hammer/ETS) por cliente: escritura 120 / 10 min, lectura 600 / min, sockets 120 / min (valores generosos para no bloquear a quienes comparten el wifi de la universidad; se midió el ataque con límites menores y el mecanismo es el mismo). Responde `429` con `Retry-After`. No se guarda ninguna IP | API4:2023, ASVS V11 |
| 2 | **Sin límite de tamaño del cuerpo**: un POST de 3 MB se aceptó (`201`) | Disponibilidad | Alta | `201` con 3 MB | Solo `application/json`, máximo 8 KB (`413` si lo supera) | API4:2023, ASVS V13 |
| 3 | **Multipart y formularios aceptados**: `multipart` escribe archivos temporales en disco y agrega superficie de ataque inútil para una API JSON | Disponibilidad | Media | `201` con multipart y urlencoded | Solo se parsea JSON; lo demás responde `415`. Se eliminaron sesión, cookies, `MethodOverride` y archivos estáticos | API8:2023, ASVS V13 |
| 4 | **Servidor de desarrollo expuesto a toda la red** (`0.0.0.0`) y con `check_origin: false`: cualquiera en el mismo Wi-Fi (por ejemplo, el de la universidad) podía usar la API, y cualquier página web podía abrir el WebSocket | Confidencialidad, Integridad | Media | `LISTEN 0.0.0.0:4000`; WebSocket con `Origin: evil.example` aceptado | Por defecto escucha solo en `127.0.0.1`; `CIVIC_LAN=1` lo abre a la red a propósito (mejor: `adb reverse tcp:4000 tcp:4000` por USB). Se quitó `check_origin: false` | ASVS V1, V14 |
| 5 | **Marcos WebSocket de tamaño ilimitado**: un marco de 2 MB se aceptó | Disponibilidad | Media | Marco de 2 MB aceptado | `max_frame_size: 4096`; el servidor cierra con código 1009 | ASVS V13 |
| 6 | **Conexiones WebSocket ilimitadas por cliente** | Disponibilidad | Media | Sin límite en el código (no se probó el ataque antes de corregir) | Límite de 120 conexiones / min por cliente (`403`) | API4:2023 |
| 7 | **Sin cabeceras de seguridad** y con `cache-control` de navegador | Confidencialidad | Baja | Solo `x-request-id` | `nosniff`, `X-Frame-Options: DENY`, `Referrer-Policy: no-referrer`, CSP `default-src 'none'`, `Cache-Control: no-store` en toda respuesta, incluidos los errores | ASVS V14.4 |
| 8 | **Texto con caracteres peligrosos en la descripción**: el byte NUL provoca una excepción de PostgreSQL sin controlar; las marcas de dirección de texto (U+202E) permiten invertir u ocultar lo que se lee ("Trojan Source" aplicado a un reporte) | Disponibilidad, Integridad | Media | `Postgrex.Error` sin controlar en los tests (en el servidor real el error se convertía en una respuesta 400 genérica, sin validación propia) | Se rechazan caracteres de control y marcas de dirección (`422`); se permiten saltos de línea, tabuladores, tildes y emojis | ASVS V5.1 |
| 9 | **Idempotencia silenciosa**: la misma `idempotency-key` con **otro contenido** devolvía el reporte viejo con `200`; el reporte nuevo se perdía sin avisar | Integridad | Media | Test rojo: la segunda llamada devolvía `200` con el reporte viejo | Se compara el contenido; si difiere responde `409 idempotency_key_conflict` | API6:2023 |
| 10 | **APK release firmado con la clave de depuración** (pública): cualquiera podría firmar una "actualización" falsa | Integridad | Alta (al publicar) | Revisión de `build.gradle.kts`: `signingConfig = debug` | La build release exige `key.properties` (ignorado por git); sin él, el APK queda **sin firmar** y no se instala. Verificado con `apksigner` | MASVS-CODE-1 |
| 11 | **Copias de seguridad de la app habilitadas** y tráfico sin cifrar no declarado explícitamente | Confidencialidad | Baja | Revisión del manifiesto: valores por defecto | `allowBackup="false"`, `usesCleartextTraffic="false"` (verificado en el APK release) | MASVS-STORAGE, MASVS-NETWORK |
| 12 | **Scripts de la demo (Leaflet) cargados de un CDN sin verificar integridad**: si el CDN se comprometiera, ejecutaría código ajeno | Integridad | Baja | Revisión del HTML generado: `<script>` sin hash | Hash SRI (sha384); los de Leaflet coinciden con los publicados oficialmente | A08:2021 |

## Controles que se verificaron y ya estaban bien

- **Inyección SQL:** todas las consultas son parametrizadas; la descripción y el `bbox` se probaron con `'); DROP TABLE incidentes; --` (tests permanentes).
- **Asignación masiva:** `cast` solo acepta `tipo`, `descripcion`, `lat` y `lng`; un `"estado":"verificado"` enviado por un atacante se ignora (probado en vivo).
- **Anonimato por diseño:** la tabla `incidentes` no tiene usuario, IP ni teléfono; los logs no guardan la IP; las respuestas no exponen `ubicacion` ni `idempotency_key`.
- **XSS:** la app Flutter pinta texto plano; el HTML de la demo escapa toda cadena del usuario.
- **Transporte de la app:** `API_URL` debe ser `https` en builds de producción (la app falla al arrancar si no lo es; probado con `validateApiUrl`); el tráfico `http` solo está permitido en la build de depuración, para la API local.
- **Permisos Android:** solo `INTERNET` y ubicación en primer plano; sin ubicación en segundo plano. La ubicación del usuario no sale del teléfono.
- **Dependencias:** 0 vulnerabilidades en backend (Hex) y en las 31 dependencias de Dart (OSV).
- **Base de datos:** solo acepta conexiones desde `127.0.0.1`.

## Riesgos pendientes o aceptados (no corregidos)

| Riesgo | Por qué queda así | Cuándo se resuelve |
|---|---|---|
| **La app se conecta a PostgreSQL como superusuario** (`postgres`) | Es desarrollo local. En producción un fallo de inyección tendría impacto máximo | Antes del piloto: rol `civic_app` sin DDL, con `statement_timeout`; migraciones con otro rol |
| **Credenciales de desarrollo en el repo público** (`postgres/postgres`, `secret_key_base` de `dev.exs`) | Solo valen en la laptop de cada integrante; la base no se expone | Producción usa variables de entorno (ya exigidas en `runtime.exs`); nunca reutilizar estos valores |
| **Sin cuentas ni autenticación**: cualquiera puede reportar | Es el alcance del avance | Iteración 1: cuentas, DNI con HMAC, límites por cuenta |
| **El límite por IP es una defensa gruesa** (valores altos por el wifi compartido de la universidad) y la ventana fija permite hasta el doble de ráfaga en el cambio de minuto | Sin cuentas no hay mejor identificador | Capas: IP alta + límite estricto por cuenta/dispositivo (iteración 1) + cupo mayor a cuentas verificadas + Play Integrity (antes del piloto). Detrás de un proxy, configurar `CLIENT_IP_HEADER` solo si el proxy sobrescribe esa cabecera |
| **Reportes falsos con ubicación falsa** (GPS simulado) | Requiere cuentas y validación comunitaria | Iteración 2 |
| **Texto libre puede contener datos personales** (un nombre, una dirección) escritos por el usuario | Mitigado: el servidor rechaza DNI, celulares, correos y enlaces (`422`) y la pantalla de reporte avisa que el reporte es anónimo. Un nombre propio no se puede detectar de forma fiable | "Reportar abuso" y moderación más adelante |
| **Fecha y hora exactas del reporte, públicas** | Son parte del producto; el anonimato depende de no guardar quién reportó | Evaluar redondear a minutos si se considera necesario |
| **Sin TLS en desarrollo** | El tráfico va por localhost o por la red local de pruebas | Producción: `force_ssl` y HSTS ya configurados en `prod.exs` |
| **El APK de depuración es depurable** | Solo para pruebas del equipo | No distribuir; releases firmados con `key.properties` |
| **Sin CI que repita estas revisiones** | Aún no hay pipeline | Agregar GitHub Actions: `mix sobelow`, `mix deps.audit`, `mix test`, `flutter analyze`, `gitleaks` |

## Cómo repetir esta revisión

```bash
cd backend
mix precommit          # compila sin avisos, formatea y corre los 58 tests
mix sobelow            # análisis estático de seguridad de Phoenix
mix deps.audit         # vulnerabilidades en dependencias
mix hex.audit          # paquetes retirados
cd ../app && flutter analyze && flutter test
```

Para probar con un teléfono físico sin exponer la API a la red: conéctalo por USB y ejecuta `adb reverse tcp:4000 tcp:4000`. Si usas Wi-Fi: `CIVIC_LAN=1 mix phx.server`, solo en una red de confianza.
