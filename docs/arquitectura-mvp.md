# Civic Security — Arquitectura del MVP

**Versión:** 0.2 (decisiones del equipo incorporadas) · **Fecha:** 2026-10-27
**Base:** `civic-security-contexto-mvp.md` + respuestas del equipo (`respuestas_preguntas_armar_arq.txt`)

Las decisiones marcadas con **[decisión técnica]** las tomó el arquitecto sin pregunta explícita al equipo; se pueden cambiar. Las decisiones confirmadas por el equipo están en la sección 18.

---

## 0. Resumen en una página

| Tema | Decisión |
|---|---|
| Estilo | **Monolito modular**: código de grano fino (módulos por dominio con fronteras estrictas), despliegue y red de grano grueso (un solo servicio, endpoints agregados). |
| App | Flutter, **Android primero** (sin Mac no hay build/push iOS) · arquitectura *feature-first* con capas internas · Riverpod · `flutter_map` + OpenStreetMap. |
| Backend | Elixir + Phoenix (el equipo ya lo conoce) · REST `/v1` + Phoenix Channels · Oban (colas persistentes en Postgres, sin Redis). |
| Datos | PostgreSQL + PostGIS (Neon, capa gratuita con respaldos) · fotos en Cloudflare R2 (10 GB gratis, URLs firmadas). |
| Tiempo real | Pines y mapa de calor en vivo por canales por **celda geohash**; el calor se agrega al escribir, así leerlo es barato. |
| Alertas push | Cliente-servidor: las zonas (Casa, Trabajo) **se guardan en el servidor** con índice grueso (celdas geohash) en claro y centro exacto **cifrado**; el servidor hace el *match* y envía FCM por token. P2P descartado para el MVP (sección 9.2). |
| Verificación de persona real | **DNI** (8 dígitos) con privacidad por diseño: solo se guarda `HMAC(DNI, clave secreta)`; nunca el número ni el nombre. Una cuenta por DNI. KYC (DNI + selfie) como proveedor enchufable a futuro. |
| Anonimato | Reporte y voto sin `usuario_id`; tokens HMAC por incidente; vínculo para reputación cifrado y **destruido** al resolverse (crypto-shredding). |
| Disponibilidad | Objetivo de demo (~95 %), pero **sin pérdida de datos** (RPO ≈ 0 con PITR + copia diaria en otro proveedor). |
| Estándares | OWASP MASVS v2 (app), OWASP ASVS nivel 2 (backend), OWASP API Top 10 2023, NIST SP 800-63B (autenticación), Ley N.º 29733. |
| Costo | USD 0/mes con capas gratuitas (ver sección 14). |

---

## 1. Requisitos y supuestos

### 1.1 Funcionales (MVP)
1. Cuenta **invitado** (sin registro) y **verificada** (alias + contraseña + verificación de persona real).
2. Crear reporte anónimo: tipo, ubicación (GPS o pin ajustado), descripción, foto opcional con rostros difuminados en el dispositivo.
3. Validación comunitaria: 3 "Lo confirmo" de cuentas verificadas a < 1 km → **Verificado**; 3 "Es falso" antes de verificarse → **Descartado**.
4. Mapa con pines + mapa de calor (filtros 1 h / 24 h / 7 días, por tipo) en tiempo real.
5. Alertas push por zonas suscritas (Casa, Trabajo) con radio.
6. Perfil: alias, estadísticas, seguridad, cerrar sesión, borrar cuenta.

### 1.2 No funcionales (cuantificados)
| Atributo | Objetivo MVP | Fuente |
|---|---|---|
| Usuarios piloto | ≤ 50, campus UCSP + Arequipa visible en el mapa | Respuestas 6, 7 |
| Latencia de alerta (reporte → push) | p95 < 60 s; objetivo de diseño < 10 s | Respuesta 8 |
| Frescura del mapa | Tiempo real (< 5 s con la app abierta) | Respuesta 9 |
| Disponibilidad | ~95 % (funciona en la demo) | Respuesta 10 |
| Pérdida de datos (RPO) | ≈ 0 para datos confirmados | Respuesta 12 |
| Tiempo de recuperación (RTO) | < 4 h | **[decisión técnica]** |
| Conectividad | Requiere datos o wifi; no hay modo offline | Respuesta 11 |
| Retención | 5 años y luego se elimina el detalle | Respuesta 15 |
| Presupuesto | USD 0/mes | Respuesta 20 |

### 1.3 Restricciones
- Equipo de 3: móvil (Flutter), backend (Elixir), diseño. Conocen MySQL/MongoDB pero no PostgreSQL; la curva es baja porque Ecto abstrae casi todo.
- **Sin Mac ni cuenta Apple Developer** → no hay build firmado iOS, TestFlight ni push iOS (APNs exige cuenta pagada). **El MVP se demuestra en Android.** iOS queda para el segundo curso (publicación en tiendas).
- Avance el **28 de octubre de 2026**; fecha del MVP final por definir.

---

## 2. Principio rector: grano fino para mantener, grano grueso para rendir

Microservicios para 3 personas y 50 usuarios multiplican la operación (redes, despliegues, consistencia distribuida) sin aportar nada. Un monolito sin fronteras se vuelve inmantenible. La solución es combinar los dos niveles:

| Dimensión | Grano fino (mantenibilidad) | Grano grueso (rendimiento y operación) |
|---|---|---|
| Código backend | 8 contextos de dominio con API pública explícita; fronteras verificadas en compilación (`boundary`) | **1 release** de Elixir, 1 contenedor, 1 base de datos |
| Código app | Un módulo por *feature* con capas `data/domain/presentation` | 1 binario; dependencias inyectadas por Riverpod |
| Red | Recursos REST bien definidos | Endpoint agregado `GET /v1/map/snapshot` (pines + calor en 1 llamada); 1 WebSocket multiplexado |
| Datos | Tablas normalizadas por contexto | Agregado precalculado `celda_calor` (se lee sin `GROUP BY` costoso) |
| Trabajo asíncrono | Un *worker* Oban por caso de uso | Una sola cola persistente en Postgres; *match* de zonas con un índice GIN y envío de push en lote |

**Ruta de evolución:** si un contexto (por ejemplo, `Alerts`) necesita escalar aparte, ya tiene su frontera y su API pública. Extraerlo a un servicio es mover código, no reescribir.

---

## 3. Vista general

```
                    ┌──────────────────────────── Teléfono (Android) ─────────────────────────────┐
                    │  Flutter app                                                                  │
                    │  ├─ features/* (auth, map, report, validation, alerts, evidence, profile)     │
                    │  ├─ ML Kit Face Detection + difuminado + re-encode (sin EXIF)                │
                    │  ├─ flutter_secure_storage (tokens, código de recuperación jamás)            │
                    │  └─ Registro de token FCM + zonas de alerta (CRUD contra el servidor)        │
                    └───────┬───────────────────────┬────────────────────────┬────────────────────┘
                     HTTPS (REST /v1)        WSS (Phoenix Channels)     PUT firmado (foto)
                            │                       │                        │
                    ┌───────▼───────────────────────▼──────┐          ┌──────▼───────────┐
                    │  Phoenix (1 release, grano grueso)    │          │  Cloudflare R2    │
                    │  ┌────────────── contextos ─────────┐ │          │  evidencias       │
                    │  │ Accounts  Verification  Privacy  │ │          └──────────────────┘
                    │  │ Incidents Validation   Geo       │ │
                    │  │ Evidence  Alerts                 │ │──FCM HTTP v1 (token)──► Firebase Cloud
                    │  └──────────────────────────────────┘ │                         Messaging ──► push
                    │  Phoenix.PubSub · Oban · Hammer (ETS) │
                    └───────────────────┬───────────────────┘
                                        │ TLS
                    ┌───────────────────▼───────────────────┐       copia lógica diaria
                    │  PostgreSQL + PostGIS (Neon)           │ ─────────────────────────► R2 (bucket backups)
                    │  datos + cola Oban + agregados de calor│
                    └────────────────────────────────────────┘
        Externos: API HIBP (k-anonimato) · Sentry (errores, sin PII) · (futuro) proveedor KYC
```

---

## 4. App móvil (Flutter)

### 4.1 Decisiones
- **Gestión de estado: Riverpod** (`flutter_riverpod` + `riverpod_generator`). Una aclaración: Riverpod no aporta seguridad en el sentido de ciberseguridad. Aporta *seguridad de tipos*: si falta una dependencia, el error aparece al compilar y no en ejecución. Se eligió sobre Bloc porque requiere menos código repetitivo para un equipo pequeño y facilita las pruebas (se sobreescriben providers). **[decisión técnica]**
- **Arquitectura: feature-first con capas internas.** Cada pantalla de Figma pertenece a una *feature*. Dentro de cada una: `presentation` (widgets + controllers) → `domain` (entidades, casos de uso, interfaces de repositorio) → `data` (DTOs, API, implementaciones).
- **Regla de fronteras:** una feature no importa el interior de otra. Lo compartido vive en `core/` o se expone como provider público de la feature.
- **Navegación:** `go_router`, con *deep links* para el Flow 2 (notificación → detalle del incidente).

### 4.2 Estructura
```
app/lib/
├── main.dart
├── app/                    # bootstrap, router, tema, ProviderScope
├── core/
│   ├── config/             # entornos (dev/prod) vía --dart-define, sin secretos
│   ├── network/            # cliente dio, interceptor de auth + refresh, reintentos con backoff
│   ├── realtime/           # socket Phoenix, gestor de suscripción a celdas
│   ├── location/           # geolocator, detección de ubicación simulada
│   ├── geo/                # geohash, cálculo de celdas que cubren un círculo/viewport
│   ├── storage/            # flutter_secure_storage, preferencias
│   └── errors/             # tipos de falla de dominio
├── features/
│   ├── onboarding/         # 01 Bienvenida
│   ├── auth/               # 02 Login, 03 Registro, 04 Código de recuperación, verificación DNI
│   ├── map/                # 05 Mapa, 05b Calor
│   ├── report/             # 06 Reportar, 06c Ajustar ubicación, 07 Enviado
│   ├── evidence/           # 06a Cámara, 06b Revisar foto (difuminado)
│   ├── incident/           # 08 Detalle + votos
│   ├── alerts/             # 09 Alertas + zonas (servidor) + registro de token FCM
│   └── profile/            # 10 Perfil
└── shared/widgets/         # componentes de diseño reutilizables
```

### 4.3 Paquetes
| Uso | Paquete |
|---|---|
| Estado / DI | `flutter_riverpod`, `riverpod_annotation`, `riverpod_generator` |
| Modelos | `freezed`, `json_serializable` |
| HTTP / tiempo real | `dio`, `phoenix_socket` |
| Mapa | `flutter_map`, `latlong2` (OSM) |
| Ubicación | `geolocator` (`isMocked` para detectar GPS falso) |
| Cámara / imagen | `image_picker` o `camera`, `google_mlkit_face_detection`, `image` (difuminado y re-encode) |
| Seguridad | `flutter_secure_storage` (Keystore en Android), `zxcvbn` |
| Push | `firebase_core`, `firebase_messaging`, `flutter_local_notifications` |
| Utilidades | `go_router`, `uuid` (v7 para claves de idempotencia), `dart_geohash` |
| Observabilidad | `sentry_flutter` (con `sendDefaultPii = false`) |

### 4.4 Confiabilidad en el cliente (sin modo offline)
- **Borrador persistente:** el reporte en curso se guarda localmente hasta que el servidor responde `201`. Si la app se cierra o falla la red, no se pierde. Esto no es modo offline: el envío sigue necesitando red. **[decisión técnica]**
- **Idempotencia:** cada reporte genera un `Idempotency-Key` (UUIDv7). Los reintentos con *backoff* exponencial + *jitter* nunca duplican reportes.
- **Reconexión del socket** automática; al reconectar se pide un `snapshot` nuevo para no perder eventos.

### 4.5 Mapa base
- **MVP:** teselas estándar de OpenStreetMap con `User-Agent` propio y caché local, acorde a la política de uso de teselas de OSM para volúmenes pequeños.
- **Al crecer:** extracto de Arequipa en **PMTiles (Protomaps)** servido desde R2 (USD 0, sin depender de servidores de terceros) o un proveedor con capa gratuita (MapTiler/Stadia). **[decisión técnica]**

---

## 5. Backend (Elixir + Phoenix)

### 5.1 Contextos (grano fino)
| Contexto | Responsabilidad | Dueño de las tablas |
|---|---|---|
| `Accounts` | Alias, contraseñas (Argon2id), sesiones, invitados, recuperación, borrado de cuenta | `usuario`, `refresh_token`, `consentimiento` |
| `Verification` | Prueba de persona real mediante proveedores enchufables: `DniHmac` (MVP), `DniKyc` (futuro) | — (escribe `usuario.verif_hash`) |
| `Privacy` | HMAC con claves versionadas, cifrado de campos (Cloak.Ecto, AES-256-GCM), retención y purga | — (funciones puras + jobs) |
| `Incidents` | Crear reporte, máquina de estados, consultas por bbox | `incidente` |
| `Validation` | Votos, regla de 3 a < 1 km, reputación | `confirmacion` |
| `Geo` | Geohash, celdas, agregado de calor | `celda_calor` |
| `Evidence` | URLs firmadas, verificación y re-encode de fotos | `evidencia` |
| `Alerts` | Zonas de alerta, tokens de dispositivo, *match* incidente→zona, broadcast por canales y push FCM | `zona_alerta`, `dispositivo` |

Reglas: un contexto solo llama a la API pública de otro, nunca a sus schemas ni a su `Repo`. Se verifica con la librería `boundary` en compilación. La comunicación asíncrona entre contextos usa jobs de Oban (persistentes) o `Phoenix.PubSub` (efímeros).

### 5.2 Estructura
```
backend/
├── lib/civic/
│   ├── accounts/  verification/  privacy/  incidents/
│   ├── validation/  geo/  evidence/  alerts/
│   └── repo.ex
├── lib/civic_web/
│   ├── controllers/api/v1/
│   ├── channels/           # UserSocket, CeldaChannel
│   ├── plugs/              # auth, rate_limit, idempotency, security_headers
│   └── router.ex
├── priv/repo/migrations/
└── test/
```

### 5.3 Librerías
`phoenix`, `ecto_sql` + `postgrex` + `geo_postgis`, `oban`, `hammer` (rate limiting en ETS), `argon2_elixir`, `joken` (JWT) o `Phoenix.Token`, `cloak_ecto` (cifrado de campos), `req` + `goth` (FCM HTTP v1), `ex_aws_s3` (firmas S3 para R2), `image` (re-encode de fotos), `geohash`, `boundary`. Para calidad y seguridad: `credo`, `sobelow`, `mix_audit`, `sentry`.

---

## 6. Modelo de datos

```
usuario
  id uuid PK · alias text UNIQUE · password_hash text (Argon2id)
  nivel enum(invitado, verificado) · verif_hash bytea UNIQUE NULL   -- HMAC-SHA256(k_verif_vN, DNI normalizado)
  recovery_hash text · reputacion int DEFAULT 0
  intentos_fallidos int · bloqueado_hasta timestamptz · creado_en timestamptz
  -- NO hay: nombre, teléfono, correo, DNI, IP

refresh_token
  id uuid PK · usuario_id FK · token_hash bytea · familia uuid · expira_en · revocado_en

consentimiento
  usuario_id FK · version text · aceptado_en timestamptz           -- evidencia para la Ley 29733

incidente
  id uuid PK (v7) · tipo enum · severidad enum(normal, alta) · descripcion text(≤500)
  ubicacion geography(Point,4326) · gh6 text · gh7 text            -- índices GiST y btree
  estado enum(sin_verificar, verificado, descartado)
  confirmaciones smallint · falsos smallint · peso numeric(2,1)    -- 1.0 verificada, 0.5 invitado
  reporter_token bytea                                             -- HMAC(usuario_id‖incidente_id, k_rep)
  ref_cifrada bytea NULL · ref_expira_en timestamptz               -- AES-256-GCM(usuario_id); se borra al resolverse
  idempotency_key uuid UNIQUE · ocurrido_en · creado_en

confirmacion
  id uuid PK · incidente_id FK · valor enum(confirmo, falso)
  voter_token bytea                                                -- HMAC(usuario_id‖incidente_id, k_vote)
  ref_cifrada bytea NULL · creado_en
  UNIQUE (incidente_id, voter_token)                               -- un voto por cuenta sin guardar quién

evidencia
  id uuid PK · incidente_id FK · objeto_key text · estado enum(pendiente, lista, rechazada)
  bytes int · creado_en
  -- fase 2: sellada_key text NULL (original cifrado para autoridad, ver sección 10)

celda_calor
  gh7 text · hora timestamptz (truncada) · tipo enum · peso_total numeric
  PK (gh7, hora, tipo)

zona_alerta
  id uuid PK · usuario_id FK ON DELETE CASCADE · nombre text(≤30)     -- "Casa", "Trabajo"
  radio_m smallint CHECK (100..2000)
  celdas text[]                -- geohash-6 que cubren el círculo; índice GIN; es el índice "grueso" (~1 km)
  centro_cifrado bytea         -- AES-256-GCM({lat,lng}) con Cloak.Ecto; solo se descifra en memoria al hacer match
  activa bool · creado_en
  -- máximo 3 zonas por cuenta

dispositivo
  id uuid PK · usuario_id FK ON DELETE CASCADE · fcm_token_cifrado bytea · plataforma enum(android, ios)
  actualizado_en               -- tokens inválidos (respuesta 404/UNREGISTERED de FCM) se borran
```

---

## 7. Desacoplar el reporte de la identidad sin perder la reputación (tema abierto 4)

**Problema:** se necesita (a) que una cuenta vote una sola vez, (b) que nadie vote su propio reporte, (c) premiar o penalizar la reputación según el resultado, y (d) que **nadie**, ni la base de datos ni la PNP, pueda saber quién reportó.

**Solución en tres piezas:**
1. **Tokens HMAC por incidente.** `voter_token = HMAC(k_vote, usuario_id ‖ incidente_id)`. Con el `UNIQUE (incidente_id, voter_token)` la deduplicación es exacta. Como el token cambia en cada incidente, no se pueden enlazar los votos de una persona entre incidentes.
2. **Bloqueo del auto-voto.** Al votar, el servidor calcula `HMAC(k_rep, votante ‖ incidente)` y lo compara con `reporter_token`. Si coinciden, rechaza el voto.
3. **Referencia temporal + crypto-shredding.** `ref_cifrada = AES-256-GCM(k_ref, usuario_id)` permite actualizar la reputación. Cuando el incidente se resuelve, un job de Oban ajusta la reputación y pone `ref_cifrada = NULL`. Si a los 7 días no se resolvió, se borra igual, sin efecto en la reputación. **[decisión técnica]**

**Riesgo residual documentado:** durante esa ventana, alguien con acceso simultáneo a la base de datos **y** a `k_ref` podría enlazar. Mitigaciones: las claves solo existen como secretos del entorno, nunca en el repo ni en la base de datos; los logs nunca registran `usuario_id` junto a `incidente_id`; los logs se retienen 7 días como máximo.

**Ante un pedido de la PNP o la Fiscalía** (respuesta 17), el sistema *estructuralmente* no tiene datos del reportante que entregar: no hay nombre, teléfono, IP ni vínculo con el usuario una vez resuelto el reporte. Es privacidad por diseño, no solo por política.

**Claves:** `k_verif`, `k_rep`, `k_vote`, `k_ref` y la clave de firma de tokens son independientes y **versionadas** (`v1`, `v2`…) para poder rotarlas sin invalidar todo.

---

## 8. API

### 8.1 REST (`/v1`, JSON, TLS obligatorio)
| Método | Ruta | Notas |
|---|---|---|
| POST | `/auth/guest` | Crea cuenta invitado; rate limit por IP en memoria (no persistida) |
| GET | `/auth/alias-suggest` | Alias tipo `Halcon-Misti-482` |
| POST | `/auth/register` | alias, contraseña (≥ 12 caracteres, revisada contra HIBP), consentimiento |
| POST | `/auth/login` · `/auth/refresh` · `/auth/logout` | Refresh rotativo con detección de reuso |
| POST | `/auth/recover` | Código de recuperación → nueva contraseña |
| POST | `/verification/dni` | `{dni}` → valida formato, calcula HMAC, marca la cuenta `verificado`; 409 si el DNI ya está en uso; 5 intentos/día por cuenta |
| GET / POST / PATCH / DELETE | `/me/zones[/:id]` | Zonas de alerta; la app envía centro + radio, el servidor calcula `celdas` y cifra el centro |
| PUT | `/me/device` | Registra o rota el token FCM del dispositivo |
| GET | `/map/snapshot?bbox&window=1h\|24h\|7d&types` | **Grano grueso:** pines + celdas de calor en 1 respuesta, con `ETag` |
| POST | `/incidents` | Header `Idempotency-Key`; responde `201 {id, estado}` |
| GET | `/incidents/:id` | Detalle + progreso de verificación (2/3) |
| POST | `/incidents/:id/votes` | `{valor, lat, lng}`; la ubicación solo se usa para validar < 1 km y **no se guarda** |
| POST | `/incidents/:id/evidence/upload-url` · `/evidence/:eid/complete` | PUT firmado a R2, máx. 2 MB, `image/jpeg` o `image/webp` |
| GET / PATCH / DELETE | `/me` | Perfil, cambio de alias y **borrado de cuenta** (derecho de cancelación de la Ley 29733) |
| GET | `/health` | Para el monitor de disponibilidad |

Formato de error uniforme: `{"error": {"code": "...", "message": "..."}}`. Nunca se devuelven *stack traces*.

### 8.2 Tiempo real (Phoenix Channels)
- Socket `/socket`, autenticado con access token (los invitados también pueden conectarse).
- Tópico `celda:<geohash6>`. La app se une a las celdas de su *viewport*, con un máximo de 30 por socket para evitar *scraping*.
- Eventos: `incidente_nuevo`, `incidente_actualizado` (cambio de estado o de contador), `calor_delta`.
- El servidor conoce las celdas de un socket **solo en memoria** mientras está conectado. No las persiste.

---

## 9. Flujos críticos

### 9.1 Crear reporte → alerta
```
App                     Phoenix                         Postgres                Oban worker            FCM / Canales
 │ POST /incidents        │                                │                       │                       │
 │ Idempotency-Key ──────►│ BEGIN                          │                       │                       │
 │                        │  INSERT incidente ────────────►│                       │                       │
 │                        │  UPSERT celda_calor (+peso) ──►│                       │                       │
 │                        │  INSERT oban_job(:alertar) ───►│  (outbox transaccional)│                       │
 │                        │ COMMIT ───────────────────────►│                       │                       │
 │◄── 201 {id, estado} ───│                                │                       │                       │
 │                        │ PubSub broadcast celda:gh6 ─────────────────────────────────────────────────────►│ (app abiertas)
 │                        │                                │── job ───────────────►│                       │
 │                        │                                │                       │── match zonas ───────►│ push por token (app cerrada)
```
- **Outbox transaccional:** el job de alerta se escribe en la misma transacción que el reporte. Si el servidor cae justo después del commit, el job sigue en la base de datos y se ejecuta al reiniciar. No se pierden alertas.
- **Política de push contra rumores** (el diferencial del producto es la *desconfianza en información no verificada*): **[decisión técnica]**
  - Reporte de cuenta verificada → push inmediato con la etiqueta "Sin verificar".
  - Reporte de invitado → push solo cuando pase a "Verificado".
  - Severidad **alta** (por ejemplo, "hay arma blanca o de fuego", una casilla del formulario) → push inmediato siempre, incluso si viene de un invitado. Esto atiende la respuesta 19: mismo trato para todos los reportes, con prioridad por el peligro.

### 9.2 Alertas por zona (cliente-servidor, ubicación exacta cifrada)
Decisión del equipo: las zonas se guardan en el servidor. Para no exponer dónde vive el usuario, se separa un **índice grueso en claro** de un **dato exacto cifrado**:

1. La app envía `POST /v1/me/zones {nombre, lat, lng, radio_m}`.
2. El servidor calcula las celdas geohash-6 (~1,2 × 0,6 km) que cubren el círculo y las guarda en `celdas` (en claro, con índice GIN). Cifra `{lat, lng}` con AES-256-GCM (Cloak.Ecto, clave fuera de la base de datos) en `centro_cifrado`.
3. Ante un reporte nuevo, el worker de Oban busca candidatos con `WHERE celdas @> ARRAY[gh6_del_incidente]`. Esta consulta solo usa el índice grueso.
4. Para cada candidato descifra el centro **solo en memoria**, calcula la distancia exacta y, si cae dentro del radio, envía FCM a los tokens de sus dispositivos. Se excluye al propio reportante.

Resultado: un volcado de la base de datos sin la clave solo revela zonas con una precisión de ~1 km, no la dirección de la casa. Las zonas se sincronizan entre dispositivos y se borran en cascada con la cuenta.

**Por qué no P2P en el MVP.** Una red de teléfonos que comparten eventos entre sí suena atractiva, pero choca con el núcleo del producto:
- **La validación comunitaria necesita una sola fuente de verdad.** En P2P cada nodo puede inventar votos o cuentas (ataque Sybil) y no hay quién imponga "3 votos de cuentas verificadas a < 1 km". Justamente el problema de WhatsApp es la información sin verificar.
- **Conectividad:** con datos móviles los teléfonos están detrás de CGNAT y no se pueden conectar directamente; Android además suspende los procesos en segundo plano. En la práctica igual haría falta un servidor de relevo.
- **Batería y privacidad:** mantener conexiones entre pares gasta batería y expone la IP de cada usuario a desconocidos.

P2P (Bluetooth / Wi-Fi Direct) queda como idea futura **de respaldo sin internet** (por ejemplo, en un sismo, algo relevante en Arequipa), no como arquitectura principal.

**Otros tipos de evento** (tráfico, choques): quedan fuera del MVP por decisión del equipo; la prioridad es la seguridad de las personas. El modelo lo soporta después agregando valores al `enum tipo`.

### 9.3 Votar → verificación (sin condiciones de carrera)
Validaciones previas: la cuenta es `verificado`, no es el reportante, está a < 1 km (`ST_DWithin`), la ubicación no es simulada y no superó el rate limit. Luego, en una sola transacción:
```sql
INSERT INTO confirmacion (...) VALUES (...);         -- falla si ya votó (UNIQUE)
UPDATE incidente
   SET confirmaciones = confirmaciones + 1,
       estado = CASE WHEN confirmaciones + 1 >= 3 THEN 'verificado' ELSE estado END
 WHERE id = $1 AND estado = 'sin_verificar'
RETURNING estado, confirmaciones;
```
(Para "Es falso" es simétrico con `falsos` → `descartado`, que además resta su peso de `celda_calor`.) El `UPDATE` condicional es atómico: dos votos simultáneos nunca producen un "cuarto voto" ni dos transiciones.

---

## 10. Evidencia fotográfica

1. Cámara o galería → **ML Kit detecta rostros → difuminado en el dispositivo** → re-encode a JPEG/WebP de 1280 px como máximo (~150 KB; elimina EXIF y GPS).
2. En la pantalla 06b el usuario ve el resultado. Se recomienda permitir **tocar para difuminar más**, porque ML Kit puede no detectar rostros de perfil o lejanos. **[decisión técnica]**
3. La app pide una URL firmada (5 min, tamaño y tipo fijados) → PUT directo a R2. El backend no recibe los bytes, lo que ahorra CPU y ancho de banda.
4. Un job de Oban descarga la foto, **re-codifica otra vez en el servidor** (defensa en profundidad contra metadatos o archivos manipulados) y la marca `lista`.
5. Para verla se generan URLs firmadas de corta duración; el bucket nunca es público.

**Entrega cifrada a autoridades (respuesta 17) — fase 2, fuera del MVP (confirmado).** Diseño previsto: la app cifra el **original sin difuminar** con la *clave pública de la autoridad* (cifrado híbrido, *sealed box* X25519 + XChaCha20-Poly1305) y lo sube como blob opaco. Ni el equipo ni el servidor pueden descifrarlo; solo la entidad con la clave privada. Requiere antes (a) una entidad con convenio que tenga la clave, y (b) base legal para subir rostros de terceros sin difuminar según la Ley 29733.

---

## 11. Verificación de persona real (tema abierto 2 y respuesta 14)

**Decisión del equipo (2026-10-27):** la cuenta verificada se obtiene con el **DNI**, priorizando la privacidad. Todo reporte sigue siendo anónimo: el DNI solo prueba "una persona = una cuenta" y nunca se vincula a reportes ni votos.

### 11.1 Flujo
1. La app envía `POST /v1/verification/dni {dni}` por TLS. El DNI no se guarda en el teléfono.
2. El servidor valida el formato (8 dígitos) y calcula `verif_hash = HMAC-SHA256(k_verif_v1, dni)`.
3. Si `verif_hash` ya existe → `409` ("Este DNI ya tiene una cuenta"). Si no, guarda el hash y marca la cuenta `verificado`.
4. El DNI en claro solo vive en memoria durante la petición. Phoenix lo filtra de los logs (`filter_parameters: ["password", "dni", ...]`) y Sentry no lo recibe.

### 11.2 Por qué HMAC y no cifrado ni SHA-256
| Opción | Problema |
|---|---|
| Guardar el DNI en claro | Una filtración expone la identidad de todos los usuarios |
| **Cifrar** el DNI (AES) | Es reversible: quien obtenga la clave recupera todos los DNIs, y el sistema "tiene" los DNIs ante cualquier pedido de datos. Además, nunca necesitamos volver a leer el DNI, solo saber si ya se usó |
| SHA-256 simple | Solo hay 10⁸ DNIs posibles: se recorren todos en segundos y se revierte el hash |
| **HMAC con clave secreta** ✅ | Irreversible para quien tenga solo la base de datos; permite comprobar duplicados. La clave vive como secreto del entorno, nunca en la base de datos ni en el repo, y está versionada para poder rotarla |

**Riesgo residual:** si un atacante obtiene **a la vez** la base de datos y `k_verif`, puede recorrer los 10⁸ DNIs y revertir los hashes. Mitigación: clave separada de las demás, acceso mínimo a los secretos y rotación. A futuro se puede guardar `k_verif` en un KMS o HSM, de modo que el servidor pida el HMAC sin conocer nunca la clave.

### 11.3 Limitación conocida (aceptada para el MVP)
Escribir un DNI no prueba que la persona sea su titular: alguien puede usar el DNI de otro. Mitigaciones del MVP: una cuenta por DNI, 5 intentos por día por cuenta y aviso en la UI de que suplantar a otra persona es delito. No se consultan APIs de RENIEC porque devuelven el nombre de la persona y eso rompe la minimización de datos.

### 11.4 Evolución: proveedor enchufable (patrón *strategy*)
| Fase | Proveedor | Qué prueba | Qué se guarda |
|---|---|---|---|
| **MVP** | `DniHmac` | Una cuenta por número de DNI | Solo `HMAC(DNI)` |
| Producción | `DniKyc`: KYC de terceros (DNI + selfie + prueba de vida) | Que la persona es la titular | Solo `HMAC(DNI)` + "verificado = sí"; **nunca** el DNI, el nombre ni las fotos (el proveedor las procesa y no las devuelve) |

Como ambas fases guardan el mismo `HMAC(DNI)`, al pasar a KYC las cuentas existentes no se pierden: solo se les pide completar la prueba de vida. **No se cobra la verificación al usuario** (respuesta 22): frena la adopción y un pago con tarjeta crea un vínculo de identidad nuevo.

---

## 12. Seguridad

### 12.1 Modelo de amenazas (resumen)
| Actor | Objetivo | Controles principales |
|---|---|---|
| Creador de cuentas falsas (Sybil) | Inflar o falsear verificaciones | Verificación institucional, `verif_hash` único, invitados sin voto, rate limits |
| Brigada de votos | Descartar reportes reales con 3 "falso" | Solo verificados a < 1 km, detección de ubicación simulada. **Riesgo aceptado en el MVP**; al crecer, ponderar votos por reputación |
| Agresor que quiere identificar al reportante | Represalia | Sin identidad en el reporte, tokens HMAC, crypto-shredding, sin IP, sin EXIF, rostros difuminados, aviso en la UI: "la ubicación del pin es pública; ajústala si reportas desde tu casa" |
| Atacante externo de la API | Robo de datos, abuso, DoS | Controles de la tabla 12.2, rate limits, validación estricta |
| *Insider* o proveedor de hosting | Correlacionar datos | Minimización (no hay qué correlacionar), secretos fuera de la base de datos, logs sin PII y con retención corta |
| Robo del teléfono | Uso de la sesión | Tokens en Keystore, refresh revocable, cierre de sesión remoto vía recuperación |

### 12.2 Controles mapeados a estándares
| Control | Implementación | Estándar |
|---|---|---|
| Contraseñas | ≥ 12 caracteres, sin reglas de composición, chequeo HIBP con k-anonimato, `zxcvbn`, Argon2id (m = 19 MiB, t = 2, p = 1 como mínimo) | NIST 800-63B §5.1.1; ASVS V2 |
| Fuerza bruta | Retardo exponencial por cuenta + rate limit por IP (en memoria) | NIST 800-63B §5.2.2; API4:2023 |
| Sesiones | Access token de 15 min; refresh opaco de 30 días, rotativo, guardado como hash, con revocación de toda la familia si se reutiliza | ASVS V3; MASVS-AUTH |
| Autorización | Verificación de propiedad en cada recurso (`/me`, votos) y del nivel de cuenta en el servidor, nunca solo en la app | API1:2023 (BOLA); ASVS V4 |
| Abuso de flujos de negocio | Límites: reportes 3/h (invitado), 6/h (verificado); votos 30/h; OTP 3 envíos/h | API6:2023 |
| Transporte | Solo TLS 1.2+ (1.3 preferido), HSTS, `cleartextTrafficPermitted=false` en Android | MASVS-NETWORK; ASVS V9 |
| Almacenamiento en el dispositivo | Tokens solo en `flutter_secure_storage`; el código de recuperación se muestra una vez y nunca se guarda; nada sensible en logs | MASVS-STORAGE |
| Privacidad | Sin nombre, teléfono, IP ni EXIF; difuminado; HMAC; crypto-shredding; zonas solo locales | MASVS-PRIVACY; Ley 29733 |
| Validación de entradas | Changesets de Ecto con listas blancas, longitud máxima, tipo enumerado, coordenadas dentro del bbox de Arequipa | ASVS V5 |
| Archivos | URL firmada con tamaño y MIME fijos, re-encode en el servidor, bucket privado | ASVS V12 |
| Secretos | Variables de entorno del hosting / GitHub Actions secrets; `gitleaks` en pre-commit y CI; nada en la app | ASVS V6; MASVS-CODE |
| Acceso administrativo | **2FA con TOTP (RFC 6238)** obligatorio en GitHub, hosting, Neon/Supabase y Cloudflare para los 3 integrantes; rotación de credenciales cuando alguien sale del equipo | NIST 800-63B AAL2; ASVS V2 |
| Acceso a la base de datos | La BD no se expone a internet (solo Phoenix se conecta, con TLS); usuario de aplicación con mínimo privilegio (sin superusuario, sin DDL); las migraciones corren con otro usuario. A futuro: credenciales dinámicas de corta vida (HashiCorp Vault o tokens IAM) | ASVS V1, V6; principio de mínimo privilegio |
| Cifrado en reposo | Cifrado de disco del proveedor (transparente, costo ≈ 0) + cifrado de campo **solo** para datos sensibles que hay que poder leer (centro de zona, token FCM, `ref_cifrada`); HMAC para lo que solo se compara (DNI) | ASVS V6 |
| Código de la app | `--obfuscate --split-debug-info`, sin secretos embebidos, detección de ubicación simulada; Play Integrity en fase 2 | MASVS-RESILIENCE |
| Dependencias | Dependabot, `mix_audit`, `mix hex.audit`, OSV-Scanner para `pubspec.lock` | ASVS V14 |
| Análisis estático | `sobelow` (seguridad Phoenix), `credo`, `flutter analyze` con lints estrictos | ASVS V14 |
| Errores y logs | Sentry con PII desactivada, sin IP; los logs no unen `usuario_id` con `incidente_id`; retención de 7 días | ASVS V7 |

### 12.3 Ley N.º 29733 (checklist del MVP)
Consentimiento informado y versionado (`consentimiento`) · finalidad explícita en la política de privacidad · derechos ARCO: exportar (`GET /me`) y borrar (`DELETE /me`) · minimización · plazo de retención definido (sección 15). Antes de operar con usuarios reales fuera del piloto académico: inscribir el banco de datos ante la Autoridad Nacional de Protección de Datos Personales.

---

## 13. Disponibilidad y confiabilidad

Una aclaración sobre la respuesta 12: **el escalado horizontal no evita perder datos.** Eso lo logran los respaldos y la replicación. El escalado horizontal da capacidad y tolerancia a caídas de instancias. Por eso el diseño los separa:

| Objetivo | Mecanismo en el MVP |
|---|---|
| **No perder datos (RPO ≈ 0)** | Postgres gestionado (Neon) con restauración a un punto en el tiempo + `pg_dump` diario cifrado a R2 (otro proveedor, otra copia) + prueba de restauración mensual |
| No perder trabajo en curso | Oban guarda los jobs en Postgres y los reintenta con *backoff*; outbox transaccional |
| No duplicar | `Idempotency-Key` en reportes; `UNIQUE` en votos |
| Autorrecuperación | Supervisores OTP de Elixir: un proceso que falla se reinicia solo, sin tumbar el nodo; *health check* del hosting reinicia el contenedor |
| Degradación controlada | Si FCM falla, el reporte igual se guarda y se ve en el mapa; si R2 falla, el reporte sale sin foto |
| Detección | UptimeRobot (gratis) sobre `/health` cada 5 min → aviso a Telegram/Discord del equipo; Sentry para errores; Phoenix LiveDashboard protegido |
| Guardia (respuesta 13) | Rotación semanal entre los 3 durante el piloto; runbook de una página: reiniciar, revisar Sentry, restaurar respaldo |

**Ruta a escala horizontal (cuando haya usuarios reales):**
1. La app Phoenix es *stateless* (la sesión va en el token y el estado en Postgres) → N instancias detrás del balanceador.
2. Clúster de nodos Elixir (`DNSCluster`) → `Phoenix.PubSub` distribuido sin cambiar código.
3. Oban ya funciona en multinodo.
4. El rate limit de Hammer pasa de ETS a un backend compartido.
5. Postgres: primero escalado vertical, luego réplicas de lectura para `map/snapshot`; particionar `incidente` por año cuando pase del millón de filas.
6. Push: con muchos usuarios por celda, el *match* de zonas pasa a enviar lotes con FCM *multicast* (hasta 500 tokens por llamada) desde varios workers de Oban en paralelo.

---

## 14. Infraestructura (USD 0/mes)

> Las condiciones de las capas gratuitas cambian. Verificarlas al crear las cuentas.

| Pieza | Servicio | Nota |
|---|---|---|
| Backend Phoenix | Hasta la iteración 4: **local** (`docker compose` en la laptop; teléfonos Android en la misma red Wi-Fi). Para el piloto: **Fly.io** (~USD 0–5/mes, cubrible con créditos educativos) **o** VM *Always Free* de Oracle Cloud (USD 0 estricto, más operación) | Se decide en la iteración 5 |
| PostgreSQL + PostGIS | Neon (capa gratuita) | Gestionado, con restauración |
| Fotos y respaldos | Cloudflare R2 | 10 GB gratis, sin costo de salida |
| Push | Firebase Cloud Messaging | Gratis |
| Errores | Sentry (Developer gratis) | Flutter + Elixir |
| Monitoreo | UptimeRobot | Gratis |
| CI/CD | GitHub Actions | Minutos gratis |
| Desarrollo local | `docker compose` con imagen `postgis/postgis` | |

No se usa la capa gratuita de Render, porque duerme el servicio tras inactividad y rompe los WebSockets y la latencia de alerta. Tampoco hace falta Redis: Oban y Hammer lo reemplazan.

---

## 15. Retención de datos (respuesta 15)
| Dato | Retención |
|---|---|
| Incidente (detalle) | 5 años → se borra; queda solo el agregado anónimo en `celda_calor` |
| Fotos de incidentes descartados | 30 días |
| Fotos de incidentes verificados o sin verificar | 1 año (comprimidas, ~150 KB) **[decisión técnica]** |
| `ref_cifrada` | Hasta resolverse o 7 días |
| Logs de aplicación | 7 días |
| Cuenta borrada | Inmediato (sus reportes ya son anónimos y se conservan) |

Purga diaria con un job programado de Oban (`Oban.Plugins.Cron`). Estimación: 50 usuarios × 5 reportes/semana × 5 años ≈ 65 000 filas. Es un volumen trivial para Postgres, así que no se particiona aún.

---

## 16. Calidad y pruebas
- **Backend:** ExUnit por contexto. **Pruebas basadas en propiedades** (`StreamData`) para la máquina de estados de votos, que es el núcleo del diferencial: "con cualquier secuencia de votos, nunca hay más de una transición". Pruebas de canal y de jobs Oban (`Oban.Testing`).
- **App:** pruebas unitarias de casos de uso y controllers (sobreescribiendo providers), pruebas de widgets de las pantallas clave y un `integration_test` del flujo reportar → ver en el mapa.
- **CI (GitHub Actions, por PR):** `mix format --check-formatted`, `credo --strict`, `sobelow`, `mix_audit`, `mix test` · `flutter analyze`, `flutter test`, `flutter build apk` · `gitleaks`.
- **Pentest interno** antes del piloto, guiado por OWASP MASTG (sobre el APK) y WSTG (sobre la API).
- Confirmar con el profesor el nivel de pruebas exigido (respuesta 28).

---

## 17. Plan de entregas
| Hito | Contenido |
|---|---|
| **Avance 28 oct** | Este documento + diagrama · monorepo creado · *walking skeleton*: app Android con mapa OSM centrado en la UCSP → formulario de reporte → `POST /v1/incidents` → Postgres → pin visible en otro teléfono en tiempo real por canal |
| Iteración 1 | Auth (invitado, registro, login, refresh, recuperación) + verificación por DNI con HMAC + consentimiento |
| Iteración 2 | **Validación comunitaria completa** (prioridad n.º 1, respuesta 23): votos, regla de 1 km, estados, reputación con crypto-shredding |
| Iteración 3 | Mapa de calor en vivo + zonas de alerta en el servidor (centro cifrado) + push FCM |
| Iteración 4 | Evidencia con difuminado + URLs firmadas + re-encode |
| Iteración 5 | Endurecimiento: rate limits, Sobelow limpio, pentest MASTG, monitoreo, runbook → **piloto con alumnos UCSP** |

Monorepo (respuesta 27):
```
civic-security/
├── app/              # Flutter
├── backend/          # Phoenix
├── infra/            # docker-compose.yml, fly.toml, scripts de respaldo
├── docs/             # arquitectura, ADRs, runbook
└── .github/workflows/  # app.yml, backend.yml (se disparan por ruta)
```

---

## 18. Decisiones confirmadas por el equipo (2026-10-27)
1. **Verificación por DNI** guardando solo `HMAC(DNI)`; no se usa correo institucional. Todo reporte es anónimo (sección 11).
2. **Zonas de alerta en el servidor** (cliente-servidor), con índice grueso en claro y centro exacto cifrado. P2P descartado para el MVP (sección 9.2).
3. **Demo solo en Android**; iOS más adelante.
4. **Original cifrado para la PNP:** a futuro, fuera del MVP.
5. **Eventos de tráfico y choques:** fuera del MVP; la prioridad es la seguridad de las personas.
6. **Hosting:** desarrollo local hasta la iteración 4; Fly.io u Oracle se decide antes del piloto.

## 19. Qué revisar al crecer
- Umbral fijo de 3 votos → ponderado por reputación y densidad de usuarios por zona (3 votos son muchos en una zona vacía y pocos en el centro).
- Brigadas de votos y GPS falso → Play Integrity / App Attest y señales de reputación.
- Teselas OSM → PMTiles propios.
- Una instancia → clúster + réplicas (sección 13).
- Moderación: hoy no hay panel. Para contenido ilegal (por ejemplo, datos personales en una descripción) el equipo usa una tarea `mix` en consola remota. Si el volumen crece: botón "Reportar abuso" y un panel LiveView interno, que es para el equipo y no para entidades externas (respuesta 26).
- Panel B2G para municipalidades: producto separado que consume agregados anónimos.
