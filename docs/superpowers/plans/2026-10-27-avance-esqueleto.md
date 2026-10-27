# Avance: esqueleto de punta a punta — Plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Objetivo:** que un reporte creado en un Android aparezca como pin, en tiempo real, en el mapa de otro Android (o del emulador).

**Arquitectura:** PostgreSQL+PostGIS en Docker; un backend Phoenix con un contexto `Incidents`, dos endpoints REST (`POST /v1/incidents`, `GET /v1/map/snapshot`) y un canal `mapa:arequipa`; una app Flutter *feature-first* con Riverpod, `flutter_map` (OSM) y pin fijo al centro para ubicar el reporte. Es el recorte mínimo de la arquitectura v0.2: sin cuentas, votos, fotos, calor ni push.

**Stack:** Docker Compose · `postgis/postgis:17-3.5` · Elixir 1.17 / Phoenix 1.8.7 · Ecto + `geo_postgis` · Flutter 3.44 · `flutter_riverpod` · `dio` · `flutter_map` + `latlong2` · `phoenix_socket` · `uuid`

**Spec:** `docs/arquitectura-mvp.md` (v0.2), secciones 4, 5, 6, 8, 9.1 y 17 (fila "Avance 28 oct").

## Forma de trabajo (pedido del usuario)

- Una tarea a la vez. Al terminar cada una: explicar qué hace cada archivo nuevo y por qué, correr la verificación delante del usuario y **esperar a que la pruebe y pregunte** antes de seguir.
- Los commits los firma solo el usuario: **sin `Co-Authored-By` ni menciones a Claude**.

## Restricciones globales

- Tipos de incidente (valor en la API → etiqueta en la UI): `robo` → "Robo", `agresion_mujer` → "Agresión a mujer", `maltrato_animal` → "Maltrato animal", `pelea_colegio` → "Pelea en salida de colegio", `actividad_sospechosa` → "Actividad sospechosa".
- Estado inicial de todo reporte: `sin_verificar`.
- `descripcion`: opcional, se recorta (`trim`) y tiene como máximo 500 caracteres.
- Ubicación válida solo dentro del bbox de Arequipa metropolitana: lat ∈ [-16.60, -16.25], lng ∈ [-71.75, -71.40].
- Centro inicial del mapa (UCSP, sede San Lázaro): `LatLng(-16.3963, -71.5340)`, zoom 16. Ajustar con Google Maps si hace falta.
- JSON de un incidente: `{"id","tipo","descripcion","lat","lng","estado","creado_en"}`, donde `creado_en` va en ISO-8601 UTC.
- Formato de error: `{"error":{"code":"...","message":"...","fields":{...}}}`; `fields` solo aparece en los 422. Nunca se devuelven *stack traces*.
- PostGIS guarda los puntos como `{lng, lat}`. La API siempre expone `lat` y `lng` por separado.
- No se registra la IP ni datos de identidad junto al reporte. El reporte no tiene ningún campo de usuario.
- Tráfico HTTP sin cifrar **solo en la build debug de Android**; la release mantiene `cleartextTrafficPermitted=false`.
- Commits en formato Conventional Commits.

## Desviaciones conscientes respecto a la arquitectura (solo para el esqueleto)

| Arquitectura | Esqueleto | Cuándo se alinea |
|---|---|---|
| Tópicos `celda:<geohash6>` | Un solo tópico `mapa:arequipa` | Iteración 3 |
| `riverpod_generator` + `freezed` | Riverpod sin generación de código; `fromJson` escrito a mano (más fácil de entender) | Cuando el equipo domine lo básico |
| `go_router` | `Navigator.push` | Iteración 3 (deep links desde push) |
| GPS actual o pin | Solo pin fijo al centro (sin pedir permisos) | Iteración 1 |
| Rate limit, auth, `boundary` | Ninguno (el backend corre solo en la red local) | Iteraciones 1 y 5 |

## Foco de revisión

1. **Reintento de un POST** (red inestable o doble toque en "Enviar") → no se duplica el pin: el `Idempotency-Key` se genera una vez por formulario y el mapa deduplica por `id`.
2. **Caída y reconexión del socket** (la Wi-Fi se corta) → al reconectar, la app vuelve a pedir el snapshot y aparecen los reportes que se perdieron.
3. **Backend apagado al abrir la app** → el mapa se ve igual, con un aviso y un botón "Reintentar"; ni se cuelga ni queda cargando para siempre.
4. **Pin fuera de Arequipa** (el usuario arrastra el mapa lejos) → 422 con el mensaje "La ubicación debe estar dentro de Arequipa", visible en el formulario.
5. **Descripción con solo espacios** → se guarda como `null`; con 501 caracteres → error de validación en la app y en el backend.

---

## Mapa de archivos

```
infra/docker-compose.yml                         Postgres+PostGIS local
backend/                                         generado por mix phx.new (app :civic)
  config/dev.exs, config/test.exs                credenciales de la BD, bind 0.0.0.0
  lib/civic/postgres_types.ex                    registra los tipos PostGIS en Postgrex
  lib/civic/incidents.ex                         contexto: create_incident/2, list_recent/2
  lib/civic/incidents/incident.ex                schema + changeset
  lib/civic/incidents/bbox.ex                    parseo y validación de bbox
  priv/repo/migrations/*_create_incidentes.exs   tabla + extensión postgis + índices
  lib/civic_web/router.ex                        scope /v1
  lib/civic_web/controllers/health_controller.ex
  lib/civic_web/controllers/incident_controller.ex
  lib/civic_web/controllers/map_controller.ex
  lib/civic_web/controllers/incident_json.ex     serialización única de un incidente
  lib/civic_web/controllers/fallback_controller.ex  formato de error uniforme
  lib/civic_web/channels/user_socket.ex, mapa_channel.ex
app/                                             generado por flutter create (solo android)
  lib/main.dart, lib/app/app.dart
  lib/core/config/env.dart                       API_URL vía --dart-define
  lib/core/network/api_client.dart               Dio + ApiFailure
  lib/core/realtime/socket.dart                  conexión PhoenixSocket
  lib/features/incident/domain/incident.dart     Incident, IncidentType, NewIncident, Bbox
  lib/features/incident/data/incident_repository.dart
  lib/features/map/presentation/map_screen.dart, map_incidents_controller.dart
  lib/features/report/presentation/report_screen.dart, report_controller.dart
  android/app/src/debug/AndroidManifest.xml      cleartext solo en debug
```

---

### Tarea 1: Base de datos local con Docker

**Por qué:** cada integrante levanta la misma base de datos con un solo comando, sin instalar Postgres.

**Archivos:**
- Crear: `infra/docker-compose.yml`

**Interfaces:**
- Produce: Postgres en `localhost:5432`, usuario `postgres`, contraseña `postgres`, BD `civic_dev`, volumen `civic_pgdata`. Son credenciales solo para desarrollo local.

- [ ] **Paso 1:** escribir el `docker-compose.yml` con un servicio `db` (imagen `postgis/postgis:17-3.5`, puerto `5432:5432`, `POSTGRES_PASSWORD=postgres`, `POSTGRES_DB=civic_dev`, volumen con nombre y `healthcheck` con `pg_isready -U postgres`).
- [ ] **Paso 2:** levantarlo.
  Ejecutar: `docker compose -f infra/docker-compose.yml up -d && docker compose -f infra/docker-compose.yml ps`
  Esperado: `db` con estado `healthy`.
- [ ] **Paso 3:** comprobar que PostGIS está disponible.
  Ejecutar: `docker compose -f infra/docker-compose.yml exec db psql -U postgres -d civic_dev -c "CREATE EXTENSION IF NOT EXISTS postgis; SELECT postgis_version();"`
  Esperado: una fila que empieza con `3.5`.
- [ ] **Paso 4:** commit `chore(infra): add local PostGIS with docker compose`.

---

### Tarea 2: Proyecto Phoenix + `/health`

**Por qué:** el primer endpoint prueba la cadena completa (HTTP → Phoenix → BD) y servirá para el monitoreo.

**Archivos:**
- Generar: `backend/` con `mix phx.new backend --app civic --module Civic --binary-id --no-html --no-assets --no-mailer --no-dashboard --no-gettext --no-install`
- Modificar: `backend/config/dev.exs` (http `ip: {0, 0, 0, 0}`, port 4000; credenciales de la Tarea 1), `backend/config/test.exs` (misma credencial, BD `civic_test`), `backend/config/config.exs` (`filter_parameters: ["password", "dni"]` en Phoenix)
- Crear: `backend/lib/civic_web/controllers/health_controller.ex`
- Modificar: `backend/lib/civic_web/router.ex` (pipeline `:api`, `get "/health"`)
- Test: `backend/test/civic_web/controllers/health_controller_test.exs`

**Interfaces:**
- Produce: `GET /health` → `200 {"status":"ok"}` cuando `Civic.Repo` responde a `SELECT 1`; `503 {"status":"db_down"}` en caso contrario.

- [ ] **Paso 1:** generar el proyecto, `cd backend && mix deps.get`.
- [ ] **Paso 2:** test `"GET /health devuelve ok con la BD arriba"` → `assert json_response(conn, 200) == %{"status" => "ok"}`.
- [ ] **Paso 3:** ejecutar `mix test test/civic_web/controllers/health_controller_test.exs` → FALLA (ruta inexistente).
- [ ] **Paso 4:** implementar `HealthController.show/2` con `Ecto.Adapters.SQL.query(Civic.Repo, "SELECT 1", [])`.
- [ ] **Paso 5:** ejecutar `mix test` → todo PASA. Luego `mix phx.server` y desde otra terminal `curl -s http://192.168.1.7:4000/health` → `{"status":"ok"}`. Esto confirma que Phoenix escucha en la red local, no solo en localhost.
- [ ] **Paso 6:** commit `feat(backend): scaffold Phoenix API with health check`.

---

### Tarea 3: Schema `Incident` + contexto `create_incident/2`

**Por qué:** es el núcleo del dominio. Aquí viven las reglas (tipos válidos, Arequipa, longitud, idempotencia), no en el controlador.

**Archivos:**
- Modificar: `backend/mix.exs` (dep `{:geo_postgis, "~> 3.7"}`), `backend/config/config.exs` (`config :civic, Civic.Repo, types: Civic.PostgresTypes`)
- Crear: `backend/lib/civic/postgres_types.ex` — `Postgrex.Types.define(Civic.PostgresTypes, [Geo.PostGIS.Extension] ++ Ecto.Adapters.Postgres.extensions(), json: Jason)`
- Crear: `backend/priv/repo/migrations/<ts>_create_incidentes.exs`
- Crear: `backend/lib/civic/incidents/incident.ex`, `backend/lib/civic/incidents.ex`
- Test: `backend/test/civic/incidents_test.exs`

**Interfaces:**
- Tabla `incidentes`: `id uuid PK`, `tipo varchar NOT NULL`, `descripcion varchar(500) NULL`, `ubicacion geography(Point,4326) NOT NULL` (índice GiST), `estado varchar NOT NULL DEFAULT 'sin_verificar'`, `idempotency_key uuid NOT NULL UNIQUE`, `inserted_at` (índice), `updated_at` (`utc_datetime_usec`). La migración ejecuta `CREATE EXTENSION IF NOT EXISTS postgis`.
- `Civic.Incidents.Incident`: campos `tipo` (`Ecto.Enum`, los 5 valores), `descripcion`, `ubicacion` (`Geo.PostGIS.Geometry`), `estado` (`Ecto.Enum [:sin_verificar, :verificado, :descartado]`), `idempotency_key`. Campos virtuales `lat`, `lng` (`:float`) que el changeset convierte en `%Geo.Point{coordinates: {lng, lat}, srid: 4326}`.
- `Civic.Incidents.create_incident(attrs :: map, idempotency_key :: Ecto.UUID.t()) :: {:ok, :created | :existing, Incident.t()} | {:error, Ecto.Changeset.t()}`
- `Civic.Incidents.Incident.coords(Incident.t()) :: {lat :: float, lng :: float}` (lee `ubicacion`; los campos virtuales `lat`/`lng` quedan en `nil` al leer desde la BD).

- [ ] **Paso 1:** agregar la dep, `mix deps.get`, crear `PostgresTypes` y la migración; ejecutar `mix ecto.create && mix ecto.migrate` → OK.
- [ ] **Paso 2:** escribir los tests (todos en `incidents_test.exs`):
  - `"crea un incidente válido en estado sin_verificar"` → `{:ok, :created, inc}`, `inc.estado == :sin_verificar`, `Incident.coords(inc) == {-16.3963, -71.5340}`.
  - `"rechaza tipo desconocido"` (`"tipo" => "ovni"`) → `{:error, cs}`, `errors_on(cs).tipo` presente.
  - `"rechaza ubicación fuera de Arequipa"` (lat `-12.05`, lng `-77.04`, Lima) → `errors_on(cs).ubicacion == ["La ubicación debe estar dentro de Arequipa"]`.
  - `"exige lat y lng"` → errores en `lat` y `lng`.
  - `"descripción con solo espacios se guarda como nil"` → `inc.descripcion == nil`.
  - `"descripción de 501 caracteres es inválida"` → error en `descripcion`.
  - `"misma idempotency_key devuelve el mismo incidente"` → la segunda llamada da `{:ok, :existing, inc2}` con `inc2.id == inc1.id` y `Repo.aggregate(Incident, :count) == 1`.
- [ ] **Paso 3:** `mix test test/civic/incidents_test.exs` → FALLA (módulos inexistentes).
- [ ] **Paso 4:** implementar el schema y el changeset (`cast` de `tipo/descripcion/lat/lng`, `update_change(:descripcion, ...)` con trim → `nil` si queda vacía, `validate_length max: 500`, validación del bbox de la sección de restricciones, construcción del `Geo.Point`) y `create_incident/2`. Idempotencia: primero `Repo.get_by(Incident, idempotency_key: key)`; si no existe, `insert`; si el insert choca con el `unique_constraint` (carrera entre dos peticiones), volver a buscar y devolver `:existing`.
- [ ] **Paso 5:** `mix test` → PASA.
- [ ] **Paso 6:** commit `feat(backend): add Incident schema with Arequipa bbox and idempotent create`.

---

### Tarea 4: `POST /v1/incidents` con errores uniformes

**Por qué:** la app necesita un contrato estable: siempre el mismo JSON de incidente y el mismo formato de error.

**Archivos:**
- Crear: `backend/lib/civic_web/controllers/incident_controller.ex`, `incident_json.ex`, `fallback_controller.ex`
- Modificar: `backend/lib/civic_web/router.ex` (`scope "/v1"`, `post "/incidents"`)
- Test: `backend/test/civic_web/controllers/incident_controller_test.exs`

**Interfaces:**
- Consume: `Civic.Incidents.create_incident/2`.
- Produce: `CivicWeb.IncidentJSON.data(incident) :: map` con las claves de la sección de restricciones (lo reutilizan las Tareas 5 y 6).
- `POST /v1/incidents` con header `idempotency-key`: `201 {"data": incidente}` si es nuevo, `200 {"data": incidente}` si se repite, `400 {"error":{"code":"idempotency_key_required"}}` si falta o no es un UUID, `422 {"error":{"code":"validation_failed","message":"Datos inválidos","fields":{...}}}`.

- [ ] **Paso 1:** tests: `"201 con incidente nuevo"` (verificar las 7 claves y que `lat`/`lng` no estén invertidos), `"200 al repetir la misma key"` (mismo `id`), `"400 sin idempotency-key"`, `"400 con key que no es UUID"`, `"422 fuera de Arequipa"` (`fields.ubicacion`), `"la respuesta no expone ubicacion ni idempotency_key"`.
- [ ] **Paso 2:** `mix test test/civic_web/controllers/incident_controller_test.exs` → FALLA.
- [ ] **Paso 3:** implementar el controlador (`action_fallback CivicWeb.FallbackController`), `IncidentJSON` y `FallbackController` (traduce `{:error, %Ecto.Changeset{}}` a 422 con `fields` y `{:error, :idempotency_key_required}` a 400).
- [ ] **Paso 4:** `mix test` → PASA. Prueba manual:
  `curl -i -X POST http://localhost:4000/v1/incidents -H 'content-type: application/json' -H "idempotency-key: $(uuidgen)" -d '{"tipo":"robo","lat":-16.3963,"lng":-71.5340,"descripcion":"Prueba"}'` → `201`.
- [ ] **Paso 5:** commit `feat(backend): add POST /v1/incidents with uniform error format`.

---

### Tarea 5: `GET /v1/map/snapshot`

**Por qué:** es el endpoint de grano grueso de la arquitectura. Con una sola llamada al abrir el mapa llega todo lo visible; el calor se sumará a esta misma respuesta en la iteración 3.

**Archivos:**
- Crear: `backend/lib/civic/incidents/bbox.ex`, `backend/lib/civic_web/controllers/map_controller.ex`
- Modificar: `backend/lib/civic/incidents.ex` (agregar `list_recent/2`), `router.ex` (`get "/map/snapshot"`)
- Test: `backend/test/civic/incidents_test.exs` (agregar), `backend/test/civic_web/controllers/map_controller_test.exs`

**Interfaces:**
- `Civic.Incidents.Bbox.parse(String.t()) :: {:ok, {min_lng, min_lat, max_lng, max_lat}} | {:error, :invalid_bbox}`. Formato `"minLng,minLat,maxLng,maxLat"`: 4 floats, `min < max`, lng ∈ [-180,180], lat ∈ [-90,90].
- `Civic.Incidents.list_recent(bbox :: tuple, since :: DateTime.t()) :: [Incident.t()]`, ordenado por `inserted_at` descendente, máximo 500. Usa `fragment("ST_Intersects(?, ST_MakeEnvelope(?, ?, ?, ?, 4326)::geography)", ...)`.
- `GET /v1/map/snapshot?bbox=...` → `200 {"data":{"incidentes":[...]}}` con los incidentes de las últimas 24 h; `400 {"error":{"code":"invalid_bbox"}}`.

- [ ] **Paso 1:** tests: `"list_recent filtra por bbox"` (uno dentro, uno fuera del bbox `-71.54,-16.40,-71.53,-16.39`), `"list_recent excluye los más antiguos que since"` (insertar con `inserted_at` de hace 25 h), `"Bbox.parse rechaza 3 números, texto y min>max"`, `"GET snapshot 200 con incidentes"`, `"GET snapshot 400 sin bbox"`.
- [ ] **Paso 2:** `mix test` → FALLA.
- [ ] **Paso 3:** implementar `Bbox`, `list_recent/2` y `MapController.snapshot/2` (`since = DateTime.add(DateTime.utc_now(), -24, :hour)`).
- [ ] **Paso 4:** `mix test` → PASA.
- [ ] **Paso 5:** commit `feat(backend): add map snapshot endpoint with bbox filter`.

---

### Tarea 6: Canal en tiempo real `mapa:arequipa`

**Por qué:** es el diferencial que se ve en la demo. El reporte aparece en los otros teléfonos sin recargar.

**Archivos:**
- Generar: `mix phx.gen.socket User` y `mix phx.gen.channel Mapa` (crean `user_socket.ex`, `mapa_channel.ex`, `channel_case.ex` y el test). Registrar `socket "/socket", CivicWeb.UserSocket, websocket: true` en `endpoint.ex`.
- Modificar: `backend/lib/civic_web/channels/mapa_channel.ex` (solo acepta el tópico `"mapa:arequipa"`; no recibe mensajes del cliente)
- Modificar: `backend/lib/civic_web/controllers/incident_controller.ex` (broadcast tras `:created`)
- Test: `backend/test/civic_web/channels/mapa_channel_test.exs`, `incident_controller_test.exs` (agregar)

**Interfaces:**
- Socket `ws://<host>:4000/socket/websocket`, sin autenticación en el esqueleto.
- Evento `"incidente_nuevo"` en `"mapa:arequipa"`, payload = `CivicWeb.IncidentJSON.data(incident)`. Se emite **desde el controlador** con `CivicWeb.Endpoint.broadcast!/3`, para que el dominio (`Civic.*`) no dependa de la capa web.

- [ ] **Paso 1:** tests: `"join a mapa:arequipa ok"`, `"join a otro tópico → {:error, %{reason: \"unauthorized\"}}"`, y en el controlador: `CivicWeb.Endpoint.subscribe("mapa:arequipa")`, POST nuevo → `assert_receive %Phoenix.Socket.Broadcast{event: "incidente_nuevo", payload: %{"id" => id}}`; POST repetido con la misma key → `refute_receive %Phoenix.Socket.Broadcast{}`.
- [ ] **Paso 2:** `mix test` → FALLA.
- [ ] **Paso 3:** implementar el canal y el broadcast (solo para `:created`). El payload debe tener claves string, igual que el JSON HTTP.
- [ ] **Paso 4:** `mix test` → PASA. `mix format --check-formatted` → sin cambios.
- [ ] **Paso 5:** commit `feat(backend): broadcast new incidents on mapa:arequipa channel`.

---

### Tarea 7: App Flutter con mapa OSM centrado en la UCSP

**Por qué:** es la primera pantalla visible (frame 05). Sirve para validar el entorno Android y la configuración de red.

**Archivos:**
- Generar: `flutter create --org pe.civicsecurity --project-name civic_security --platforms android app`
- Dependencias: `cd app && flutter pub add flutter_riverpod dio flutter_map latlong2 phoenix_socket uuid`
- Crear: `app/lib/core/config/env.dart`, `app/lib/app/app.dart`, `app/lib/features/map/presentation/map_screen.dart`
- Modificar: `app/lib/main.dart` (`runApp(const ProviderScope(child: CivicApp()))`), `app/android/app/src/debug/AndroidManifest.xml` (`android:usesCleartextTraffic="true"` en `<application>`, solo debug)
- Modificar: `app/android/app/src/main/AndroidManifest.xml` (permiso `INTERNET`)
- Modificar: `app/analysis_options.yaml` (agregar `prefer_const_constructors`, `avoid_print`)
- Test: `app/test/widget_test.dart` (reemplazar el del contador)

**Interfaces:**
- `const String apiUrl = String.fromEnvironment('API_URL', defaultValue: 'http://10.0.2.2:4000');` (10.0.2.2 es la laptop vista desde el emulador; en un teléfono real se usa `--dart-define=API_URL=http://192.168.1.7:4000`). Se agrega `wsUrl`, derivado de `apiUrl` reemplazando `http` por `ws` y añadiendo `/socket/websocket`.
- `const ucspCenter = LatLng(-16.3963, -71.5340);`
- `MapScreen`: `FlutterMap` con `TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'pe.civicsecurity.civic_security')`, atribución "© OpenStreetMap contributors" y un ícono de pin fijo superpuesto al centro.

- [ ] **Paso 1:** test `"MapScreen muestra el mapa y el pin central"` → `expect(find.byType(FlutterMap), findsOneWidget)` y `find.byKey(const Key('pin-central'))`.
- [ ] **Paso 2:** `flutter test` → FALLA.
- [ ] **Paso 3:** implementar `env.dart`, `app.dart` (MaterialApp, `home: MapScreen()`) y `MapScreen`.
- [ ] **Paso 4:** `flutter test` → PASA; `flutter analyze` → sin issues.
- [ ] **Paso 5:** `flutter emulators --launch Pixel_9_Pro_XL`, luego `flutter run` → se ve Arequipa con la UCSP al centro. En el teléfono real: `flutter run --dart-define=API_URL=http://192.168.1.7:4000`.
- [ ] **Paso 6:** commit `feat(app): scaffold Flutter app with OSM map centered on UCSP`.

---

### Tarea 8: Modelo, repositorio y pines desde el snapshot

**Por qué:** conecta la app con el backend y fija la separación por capas: `domain` (qué es un incidente), `data` (cómo se obtiene) y `presentation` (cómo se ve).

**Archivos:**
- Crear: `app/lib/features/incident/domain/incident.dart`, `app/lib/core/network/api_client.dart`, `app/lib/features/incident/data/incident_repository.dart`, `app/lib/features/map/presentation/map_incidents_controller.dart`
- Modificar: `app/lib/features/map/presentation/map_screen.dart` (`MarkerLayer` + estados de carga y error)
- Test: `app/test/features/incident/incident_test.dart`, `app/test/features/map/map_incidents_controller_test.dart`

**Interfaces:**
- `enum IncidentType { robo, agresionMujer, maltratoAnimal, peleaColegio, actividadSospechosa }` con `String get wire` (`"agresion_mujer"`, …), `String get label` (etiquetas de las restricciones globales) y `static IncidentType? fromWire(String)`.
- `class Incident { final String id; final IncidentType tipo; final String? descripcion; final double lat, lng; final String estado; final DateTime creadoEn; factory Incident.fromJson(Map<String, dynamic>); }`
- `class NewIncident { final IncidentType tipo; final String? descripcion; final double lat, lng; Map<String, dynamic> toJson(); }`
- `class Bbox { final double minLng, minLat, maxLng, maxLat; String toQuery(); static const arequipa = Bbox(-71.75, -16.60, -71.40, -16.25); }`
- `class ApiFailure implements Exception { final String code; final String message; final Map<String, List<String>> fields; }`. Se construye con `ApiFailure.fromDio(DioException)`: sin conexión da `code: 'network'` y el mensaje "No se pudo conectar con el servidor".
- `final dioProvider = Provider<Dio>(...)` (baseUrl `apiUrl`, timeouts de 10 s).
- `abstract interface class IncidentRepository { Future<List<Incident>> fetchSnapshot(Bbox bbox); Future<Incident> create(NewIncident input, {required String idempotencyKey}); Stream<Incident> watchNew(); Stream<void> watchReconnects(); }`, con `final incidentRepositoryProvider = Provider<IncidentRepository>(...)`. En esta tarea `HttpIncidentRepository` implementa los dos primeros métodos; `watchNew`/`watchReconnects` devuelven `Stream.empty()` hasta la Tarea 10.
- `class MapIncidentsController extends AsyncNotifier<List<Incident>>`: `build()` llama a `fetchSnapshot(Bbox.arequipa)`; `void upsert(Incident)` reemplaza o agrega por `id`; `Future<void> refresh()`. Provider: `mapIncidentsProvider`.

- [ ] **Paso 1:** tests: `"Incident.fromJson lee lat y lng sin invertirlos"`, `"fromJson acepta descripcion null"`, `"IncidentType.fromWire('agresion_mujer') == agresionMujer y fromWire('ovni') == null"`, `"el controller carga el snapshot del repositorio falso"`, `"upsert con el mismo id no duplica"`, `"si fetchSnapshot lanza ApiFailure el estado es AsyncError"`. Usar un `FakeIncidentRepository` y `ProviderContainer(overrides: [incidentRepositoryProvider.overrideWithValue(fake)])`.
- [ ] **Paso 2:** `flutter test` → FALLA.
- [ ] **Paso 3:** implementar los modelos, `api_client.dart`, el repositorio y el controller. En `MapScreen`: un `Marker` por incidente con color por tipo; si el estado es `AsyncError`, `SnackBar` con `ApiFailure.message` y la acción "Reintentar" → `refresh()`; el mapa se sigue viendo debajo.
- [ ] **Paso 4:** `flutter test` → PASA; `flutter analyze` → sin issues.
- [ ] **Paso 5:** con el backend arriba y el incidente de prueba creado con `curl` en la Tarea 4, `flutter run` → se ve el pin. Con el backend apagado → aparece el aviso "Reintentar", sin crash.
- [ ] **Paso 6:** commit `feat(app): load incidents from map snapshot`.

---

### Tarea 9: Pantalla Reportar (pin fijo al centro → POST)

**Por qué:** es el flujo principal del producto (frames 06, 06c y 07, simplificados).

**Archivos:**
- Crear: `app/lib/features/report/presentation/report_controller.dart`, `report_screen.dart`
- Modificar: `map_screen.dart` (FAB "Reportar" que abre `ReportScreen(lat, lng)` con el centro actual de `MapController.camera.center`)
- Test: `app/test/features/report/report_screen_test.dart`

**Interfaces:**
- `class ReportController extends AutoDisposeNotifier<ReportState>` (o `Notifier` con `ref.onDispose`, según la API de Riverpod que quede instalada). `ReportState { bool sending; ApiFailure? failure; Incident? created; final String idempotencyKey; }`. La `idempotencyKey` (`const Uuid().v7()`) se genera **una vez** en `build()` y se reutiliza en cada reintento.
- `Future<void> submit(NewIncident input)`: ignora la llamada si ya está `sending`; si sale bien, llama a `ref.read(mapIncidentsProvider.notifier).upsert(created)`.
- `ReportScreen({required double lat, required double lng})`: `DropdownButtonFormField<IncidentType>` (obligatorio), `TextFormField` descripción (`maxLength: 500`), coordenadas en solo lectura, botón "Enviar reporte anónimo" (deshabilitado mientras `sending`). Si sale bien → `Navigator.pop` y `SnackBar` "Reporte enviado". Si falla → el texto de `failure.message` y los `fields` (por ejemplo, "La ubicación debe estar dentro de Arequipa") se ven en la pantalla.

- [ ] **Paso 1:** tests de widget: `"no envía sin tipo y muestra 'Elige un tipo'"`, `"envía con la misma idempotencyKey al reintentar tras un fallo"` (el fake falla la 1.ª vez con `ApiFailure` y acierta la 2.ª; comparar las keys recibidas), `"doble toque en Enviar hace un solo create"`, `"muestra el error de ubicación del 422"`.
- [ ] **Paso 2:** `flutter test` → FALLA.
- [ ] **Paso 3:** implementar el controller, la pantalla y el FAB.
- [ ] **Paso 4:** `flutter test` → PASA; `flutter analyze` → sin issues.
- [ ] **Paso 5:** en el emulador: mover el mapa, tocar "Reportar", elegir "Robo" y enviar → aparece el pin en el centro. Arrastrar hasta Lima y reportar → se ve el error de ubicación.
- [ ] **Paso 6:** commit `feat(app): add anonymous report form with fixed center pin`.

---

### Tarea 10: Tiempo real en la app + demo con dos dispositivos

**Por qué:** cierra el objetivo del avance.

**Archivos:**
- Crear: `app/lib/core/realtime/socket.dart`
- Modificar: `app/lib/features/incident/data/incident_repository.dart` (`watchNew`, `watchReconnects`), `map_incidents_controller.dart` (suscripciones)
- Modificar: `README.md` (sección "Cómo correr el avance", con los comandos de las Tareas 1, 2 y 7 y la IP por `--dart-define`)
- Test: `app/test/features/map/map_incidents_controller_test.dart` (agregar)

**Interfaces:**
- `final phoenixSocketProvider = Provider<PhoenixSocket>(...)`: conecta a `wsUrl` y se cierra con `ref.onDispose`.
- `HttpIncidentRepository.watchNew()`: se une a `mapa:arequipa` y emite `Incident.fromJson(payload)` para cada evento `incidente_nuevo`. `watchReconnects()`: emite cada vez que el socket se vuelve a abrir **después** de la primera conexión.
- `MapIncidentsController.build()`: escucha `watchNew()` → `upsert`, y `watchReconnects()` → `refresh()`. Cancela las suscripciones en `ref.onDispose`.

- [ ] **Paso 1:** tests: `"un incidente emitido por watchNew aparece en el estado"`, `"el mismo incidente por POST y por socket aparece una sola vez"`, `"una reconexión vuelve a pedir el snapshot"` (el fake cuenta las llamadas a `fetchSnapshot` → 2).
- [ ] **Paso 2:** `flutter test` → FALLA.
- [ ] **Paso 3:** implementar `socket.dart`, los dos streams y las suscripciones del controller.
- [ ] **Paso 4:** `flutter test` → PASA; `flutter analyze` → sin issues.
- [ ] **Paso 5 (demo):** backend con `mix phx.server`, la app en el emulador y en el teléfono real (`--dart-define=API_URL=http://192.168.1.7:4000`). Reportar desde el teléfono → el pin aparece en el emulador en menos de 2 s. Apagar y prender la Wi-Fi del emulador mientras se reporta desde el teléfono → al reconectar, el pin aparece.
- [ ] **Paso 6:** commit `feat(app): show new incidents in real time via Phoenix channel` y `git push`.
