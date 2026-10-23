# Contexto: Civic Security – MVP (curso ET201, Formación de Empresas de Base Tecnológica I, UCSP)

## 1. El producto
Red ciudadana para **reportar incidentes de forma anónima** (robos, agresión a mujeres, maltrato animal, peleas en salidas de colegios, actividad sospechosa) y **alertar en tiempo real** a quienes están cerca. Opera en Arequipa, Perú.

**Diferencial validado en entrevistas:** el dolor no es "falta de información", sino **desconfianza en información no verificada** (como en los grupos de WhatsApp). Por eso el núcleo es:
1. Reporte **anónimo y seguro**, porque la gente tiene miedo a reportar.
2. **Validación comunitaria**, para filtrar falsas alarmas.
3. **Mapa de calor** de actividad para anticipar riesgos.

**Plataforma:** app móvil en **Flutter (Dart)** para **Android e iOS**.

## 2. Decisiones de autenticación y privacidad
- **Anónimo frente a otros usuarios y autoridades; seudónimo frente al sistema.** El backend sabe que "una persona = una cuenta", pero no quién es.
- **Registro:** alias autogenerado y editable (ej. `Halcon-Misti-482`), contraseña y teléfono con OTP. **No se pide nombre ni apellido.**
- **Teléfono:** solo se usa para verificar que la persona es real y evitar cuentas falsas (ataque Sybil). Se guarda únicamente `HMAC(teléfono, clave_secreta_servidor)`, nunca el número. Un SHA-256 simple no basta, porque el espacio de números es pequeño y se puede recorrer por fuerza bruta.
- **Dos niveles de cuenta:**
  - **Invitado:** reporta sin registrarse, su reporte pesa menos y no vota.
  - **Verificada (con OTP):** vota y su reporte pesa completo.
- **Contraseñas (NIST SP 800-63B):**
  - Mínimo 12 caracteres y se permiten frases.
  - Sin reglas de composición.
  - Se rechazan contraseñas filtradas (API HIBP con k-anonymity).
  - Medidor de fuerza (`zxcvbn`).
  - Hash con **Argon2id** y límite de intentos.
- **Recuperación:**
  - Código de recuperación que se muestra una sola vez.
  - OTP al teléfono verificado.
  - Email opcional.
  - "Guardar en gestor de contraseñas" usa el gestor del sistema operativo (Google Password Manager / iCloud Keychain), no uno propio.
- **Reinstalación:** sesión en `flutter_secure_storage`. En Android, Block Store y Credential Manager; en iOS, Keychain.
- **Passkeys/huella:** aparecen en los mockups, pero quedan **fuera del MVP**.
- **Fotos:**
  - Son opcionales; el reporte no empieza por la foto.
  - **Difuminado automático de rostros en el dispositivo** (ML Kit) antes de subirlas.
  - Se eliminan los metadatos EXIF (GPS, modelo del equipo).
  - El difuminado de **placas queda fuera del MVP**, porque ML Kit no las detecta de forma nativa y requeriría un modelo propio.
- No se guarda la IP junto al reporte.
- Consentimiento conforme a la **Ley N.º 29733** de protección de datos.

## 3. Reglas de negocio
- Reporte nuevo → **"Sin verificar"**.
- **3 confirmaciones** de cuentas verificadas a **menos de 1 km** → **"Verificado"**.
- **3 votos "Es falso"** antes de verificarse → **"Descartado"**.
- Los votos son anónimos.
- **Ubicación del reporte:** se usa el GPS actual, o el usuario mueve el mapa con un pin fijo al centro para marcar el lugar exacto (por ejemplo, si el incidente ocurre a una cuadra).
- **Mapa de calor:** densidad de reportes por zona y franja horaria, con filtros de última hora, 24 h y 7 días.
- **Alertas:** el usuario suscribe zonas (Casa, Trabajo) con un radio y recibe notificaciones push.

## 4. Mockups (Figma, página "App - MVP", prototipo navegable, referencia 390×844 = iPhone 13/14)
Link: https://www.figma.com/design/DUsoMI54iOjOxD648BoRTG/Civic-Security-MVP-Mockups

| Frame | Pantalla |
|---|---|
| 01 | Bienvenida |
| 02 | Login (alias o teléfono, contraseña, passkey, "Reportar sin cuenta", "Regístrate") |
| 03 | Registro (alias generado, contraseña con medidor, teléfono + OTP, consentimiento) |
| 04 | Código de recuperación, con overlay "Guardar en gestor de contraseñas" |
| 05 | Mapa (inicio): buscador, filtros por tipo, pines, zonas de calor, botón Reportar, hoja inferior, tabs Mapa / Alertas / Perfil |
| 05b | Mapa de calor con zoom: filtros de tiempo, leyenda, callout "Zona de alta actividad" |
| 06 | Reportar: tipo de incidente, ubicación, descripción, foto opcional, "Enviar reporte anónimo" |
| 06a | Cámara |
| 06b | Revisar foto: difuminado, "Tomar otra", "Usar foto", "Cancelar reporte" |
| 06c | Ajustar ubicación: pin fijo al centro y distancia al usuario |
| 07 | Reporte enviado (botón "Llamar al 105" y "Ver en el mapa") |
| 08 | Detalle del incidente: progreso de verificación 2/3, "Lo confirmo" / "Es falso", con overlays de agradecimiento |
| 09 | Alertas: mis zonas y lista con estados verificado / sin verificar / descartado |
| 10 | Perfil: alias, estadísticas, seguridad, privacidad, cerrar sesión |
| 11 | Notificación push en la pantalla de bloqueo de iOS (entrada alternativa a la app) |
| 12 | Widget de acceso rápido en Android (entrada alternativa a la app) |

**Flujos del prototipo:**
- **Flow 1:** desde la Bienvenida.
- **Flow 2:** desde la notificación push.
- **Flow 3:** desde el widget.

Al terminar cualquier acción, el usuario queda dentro de la app, en el **05 Mapa**.

## 5. Propuesta preliminar de stack (para debatir)
- **App:** Flutter
  - `flutter_map` + OpenStreetMap (alternativa: Google Maps SDK)
  - `geolocator`, `camera` / `image_picker`
  - Google ML Kit (Face Detection)
  - `flutter_secure_storage`
  - Riverpod o Bloc
- **Backend:** **Elixir + Phoenix**
  - REST + **Phoenix Channels** (WebSocket) para alertas en tiempo real
  - JWT + refresh token
  - Panel de moderación en LiveView
  - *Alternativa más rápida:* Firebase (Auth + Firestore + FCM), con consultas geoespaciales y mapa de calor más limitados.
- **Datos:**
  - **PostgreSQL + PostGIS** (consultas por radio; mapa de calor con `ST_SnapToGrid` o índice H3)
  - Almacenamiento S3-compatible para fotos (Cloudflare R2 / MinIO), con URLs firmadas
  - Redis opcional para rate limiting
- **Push:** Firebase Cloud Messaging (entrega en Android e iOS vía APNs).
- **OTP:** Twilio o Firebase Phone Auth.
- **Infraestructura:** Docker en Fly.io o VPS, GitHub + GitHub Actions.
- **Entidades:** `usuario`, `incidente`, `confirmacion`, `evidencia`, `zona_suscrita`.

## 6. Fuera del MVP
Passkeys, widget nativo (requiere código nativo: WidgetKit en iOS, App Widgets en Android), difuminado de placas, video como evidencia, integración con Serenazgo/PNP, panel B2G para municipalidades.

## 7. Temas abiertos para debatir
1. Elixir/Phoenix o Firebase según el tiempo y las habilidades del equipo (3 personas).
2. Si el OTP por teléfono será obligatorio para la cuenta verificada, considerando la percepción de anonimato (en Perú los chips están registrados con DNI).
3. Estructura del proyecto Flutter (feature-first o capas), manejo de estado y modo offline.
4. Diseño de la API y del modelo de datos, y cómo desacoplar el reporte de la identidad sin perder la reputación del usuario.
5. Estrategia de pruebas y plan de entregas del MVP.
