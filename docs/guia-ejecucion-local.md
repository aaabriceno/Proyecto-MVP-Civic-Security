# Guía para ejecutar Civic Security en local

Paso a paso para levantar **la base de datos, el servidor y la app en una tablet o teléfono Android**, todo desde tu computadora. Está pensada para que cualquiera del equipo lo repita sin preguntar.

> **Probado el 2026-11-11** en Ubuntu 24.04 con una tablet Lenovo TB350XU (Android). Los comandos de terminal son de Linux/macOS. En Windows, usa WSL o adapta los pocos comandos propios de Linux (`ss`, `pkill`, `hostname -I`); los de `adb`, `flutter`, `mix` y `docker` son iguales.

## Contenido

1. [Qué se levanta y cómo se conecta](#1-qué-se-levanta-y-cómo-se-conecta)
2. [Requisitos](#2-requisitos)
3. [Primera vez (se hace una sola vez)](#3-primera-vez-se-hace-una-sola-vez)
4. [Camino A: tablet por cable USB (recomendado)](#4-camino-a-tablet-por-cable-usb-recomendado)
5. [Camino B: tablet por Wi-Fi, sin cable](#5-camino-b-tablet-por-wi-fi-sin-cable)
6. [Probar el flujo de cuentas](#6-probar-el-flujo-de-cuentas)
7. [Datos de demostración (los pines del mapa)](#7-datos-de-demostración-los-pines-del-mapa)
8. [Pruebas automáticas](#8-pruebas-automáticas)
9. [Apagar todo](#9-apagar-todo)
10. [Problemas frecuentes](#10-problemas-frecuentes)
11. [Referencia: puertos y variables](#11-referencia-puertos-y-variables)

---

## 1. Qué se levanta y cómo se conecta

Son **tres piezas**, todas en tu computadora salvo la app:

```
┌────────────────────────── tu computadora ───────────────────────────┐
│                                                                     │
│   PostgreSQL + PostGIS      Servidor Phoenix (Elixir)               │
│   (Docker, puerto 5432) ◄── (puerto 4000)                           │
│   los datos                 la API y el canal en tiempo real        │
│                                      ▲                              │
└──────────────────────────────────────┼──────────────────────────────┘
                                       │  USB  (adb reverse)
                                       │  o Wi-Fi (IP de la computadora)
                              ┌────────┴─────────┐
                              │  App Flutter     │
                              │  en la tablet    │
                              └──────────────────┘
```

La tablet tiene que **llegar al servidor de tu computadora**. Hay dos formas:

| | **Camino A: USB** | **Camino B: Wi-Fi** |
|---|---|---|
| Necesita | Cable de datos y depuración USB | Misma red Wi-Fi y un cambio en el servidor |
| Dirección que usa la app | `http://127.0.0.1:4000` | `http://<IP de tu computadora>:4000` |
| Seguridad | El servidor solo es visible para tu computadora | El servidor queda visible para **toda la red** mientras dure la prueba |
| Cuándo usarlo | Desarrollo diario | Probar con varias personas o sin cable |

Si dudas, usa el **Camino A**.

---

## 2. Requisitos

| Herramienta | Versión con la que se probó | Cómo comprobarla |
|---|---|---|
| Docker y Docker Compose | 29.x y 2.40 | `docker --version` y `docker compose version` |
| Elixir y Erlang/OTP | 1.17.3 y OTP 27 | `elixir --version` |
| Flutter | 3.44.5 (canal estable) | `flutter --version` |
| `adb` (Android platform-tools) | 1.0.41 | `adb version` |
| Java (JDK) | 21 | `java -version` |
| Una tablet o teléfono Android con cable USB | | |

Además, en la tablet hay que activar la **depuración por USB** (ver el paso 4.3). Y la tablet necesita **internet**: los mosaicos del mapa se descargan de OpenStreetMap.

`flutter doctor` te dice si falta algo del lado de Android.

---

## 3. Primera vez (se hace una sola vez)

### 3.1 Clonar el repositorio

```bash
git clone https://github.com/aaabriceno/Proyecto-MVP-Civic-Security.git
cd Proyecto-MVP-Civic-Security
```

> Si tu carpeta tiene espacios en el nombre (por ejemplo `Semestre 2026-2`), no hay problema: el proyecto ya lo maneja, solo compila una librería en `~/.cache/civic_security`.

### 3.2 Levantar la base de datos

```bash
docker compose -f infra/docker-compose.yml up -d
```

Crea un contenedor llamado `civic_db` (PostgreSQL 17 con PostGIS) que guarda los datos en un volumen de Docker. Comprueba que esté sano:

```bash
docker compose -f infra/docker-compose.yml ps
```

Debe decir `Up ... (healthy)`.

### 3.3 Preparar el servidor

```bash
cd backend
mix setup
```

`mix setup` hace cuatro cosas: descarga las dependencias, crea la base `civic_dev`, crea las tablas y **siembra 80 incidentes de prueba**. Si Elixir te pregunta si quieres instalar **Hex** o **rebar**, responde `Y`.

> ⚠️ **Solo la primera vez.** La siembra borra los incidentes de desarrollo que haya y los vuelve a crear. Si solo quieres arrancar el servidor otro día, salta al paso 4.

### 3.4 Preparar la app

```bash
cd ../app
flutter pub get
```

Listo. Desde aquí, todos los días solo necesitas el Camino A o el B.

---

## 4. Camino A: tablet por cable USB (recomendado)

Cada vez que quieras trabajar, estos pasos en orden.

### 4.1 Base de datos arriba

```bash
docker compose -f infra/docker-compose.yml up -d
```

Si ya estaba corriendo, no pasa nada.

### 4.2 Servidor

En una terminal, déjala abierta:

```bash
cd backend
mix phx.server
```

Verás los registros de cada petición. Comprueba en **otra** terminal que responde:

```bash
curl http://127.0.0.1:4000/health
```

Debe contestar `{"status":"ok"}`.

### 4.3 Preparar la tablet (solo la primera vez)

1. Ajustes → **Acerca de la tablet** → toca **7 veces** "Número de compilación". Aparece "Ya eres desarrollador".
2. Ajustes → **Sistema → Opciones de desarrollador** → activa **Depuración por USB**.
3. Conecta la tablet con un **cable de datos** (algunos cables solo cargan).
4. En la tablet aparece "¿Permitir depuración por USB?" → marca "Permitir siempre" y acepta.
5. Evita que la pantalla se apague y se bloquee mientras pruebas.

### 4.4 Comprobar que la computadora ve la tablet

```bash
adb devices
```

Debe salir una línea con un código y la palabra `device`:

```
HVA5KEYM    device
```

Ese código (aquí `HVA5KEYM`) es el **id de tu tablet**. Si sale `unauthorized`, acepta el aviso en la tablet; si no sale nada, mira el [apartado de problemas](#10-problemas-frecuentes). También puedes verlo con `flutter devices`.

### 4.5 Abrir el puente entre la tablet y el servidor

```bash
adb reverse tcp:4000 tcp:4000
```

Esto hace que, cuando la app pida `127.0.0.1:4000` (la propia tablet), la petición viaje por el cable hasta el puerto 4000 de tu computadora. **Hay que repetirlo** cada vez que desconectes el cable o reinicies la tablet.

Para ver los puentes activos: `adb reverse --list`.

### 4.6 Correr la app

```bash
cd app
flutter run -d HVA5KEYM --dart-define=API_URL=http://127.0.0.1:4000
```

(Cambia `HVA5KEYM` por el id de tu tablet.) La primera vez tarda unos minutos en compilar.

- `--dart-define=API_URL=...` le dice a la app **a qué servidor hablar**. Se fija al compilar: si cambias la dirección, hay que volver a correr `flutter run`.
- La app pide **permiso de ubicación**: acepta "Mientras la app está en uso".

### 4.7 Qué deberías ver

1. La **bienvenida** de Civic Security, con un mapa ilustrado y el botón "Comenzar".
2. Con "Comenzar" → "Ver el mapa sin cuenta", el **mapa de Arequipa** con pines y la etiqueta verde **"En vivo"**. "En vivo" significa que el canal en tiempo real conectó con el servidor.

### 4.8 Teclas útiles mientras `flutter run` está abierto

| Tecla | Qué hace |
|---|---|
| `r` | Recarga en caliente (aplica tus cambios de código sin perder el estado) |
| `R` | Reinicio en caliente (reinicia la app) |
| `q` | Cierra `flutter run` en la computadora. **La app sigue en la tablet**, pero sin conexión de depuración |
| `h` | Lista todas las teclas |

### 4.9 Probar el rendimiento (modo *profile*)

El modo normal (depuración) es entre 3 y 10 veces más lento que la app real, así que no sirve para juzgar la fluidez. Para eso:

```bash
flutter run --profile -d HVA5KEYM --dart-define=API_URL=http://127.0.0.1:4000
```

La medición automática y sus resultados están en [rendimiento-mapa.md](rendimiento-mapa.md).

---

## 5. Camino B: tablet por Wi-Fi, sin cable

Sirve para no depender del cable o para que **varias personas** prueben contra tu computadora.

> ⚠️ **Qué estás haciendo:** abrir el servidor a toda la red. Mientras esté así, cualquiera en esa red puede hablarle. Úsalo solo en una red de confianza (la de tu casa), con datos de prueba, y apágalo al terminar.

> ⚠️ **La red tiene que permitirlo.** Muchas redes públicas o de universidad aíslan a los dispositivos entre sí y la tablet no vería tu computadora. Si no conecta, pasa de seguro por eso.

### 5.1 Confirma que la tablet y la computadora están en la misma red

Es el paso donde más se falla. La tablet solo puede llegar a tu computadora si **las dos están en la misma red**, y eso hay que comprobarlo, no suponerlo.

**Primero, la IP de tu computadora:**

```bash
ip -4 route get 1.1.1.1 | grep -o 'src [0-9.]*'
```

Muestra la IP que usa tu computadora para salir a internet, por ejemplo `src 192.168.1.7`. Esa es la que va en la `API_URL`. (`hostname -I` también sirve, pero lista varias y entre ellas están las de Docker, que no son tu Wi-Fi.) Las redes privadas usan uno de estos rangos:

| Rango | Ejemplo | Suele ser |
|---|---|---|
| `192.168.x.x` | `192.168.1.7` | Wi-Fi de casa |
| `10.x.x.x` | `10.0.0.25` | Algunas casas y oficinas |
| `172.16.x.x` a `172.31.x.x` | `172.20.10.6` | Hotspot de iPhone y redes de universidad |

**Después, la red de la tablet** (con la tablet conectada por cable):

```bash
adb shell ip -4 addr show wlan0 | grep -o 'inet [0-9./]*'
adb shell dumpsys wifi 2>/dev/null | grep -m1 -o 'SSID: "[^"]*"'
```

Compara las dos IP: en la mayoría de las redes, los **tres primeros números deben ser iguales**.

| Computadora | Tablet | Resultado |
|---|---|---|
| `172.20.10.6` | `172.20.10.13` | Misma red. Sigue. |
| `172.20.10.6` | `172.16.176.37` | **Redes distintas.** La tablet no puede ver a la computadora. En Ajustes → Wi-Fi, conecta una de las dos a la red de la otra. |

> 📱 **Si usas el hotspot del celular:** funciona, pero ten en cuenta que (1) tu IP cambia cada vez que cambias de red y hay que volver a compilar la app (paso 5.4); (2) el mapa descarga sus mosaicos por esa conexión y gasta tus datos móviles; (3) algunas redes no dejan que los dispositivos se vean entre sí, y eso solo se descubre en el paso 5.3.

### 5.2 Levanta el servidor abierto a la red

```bash
cd backend
CIVIC_LAN=1 mix phx.server
```

`CIVIC_LAN=1` hace que escuche en todas las interfaces (`0.0.0.0`) y no solo en `127.0.0.1`. Sin esa variable, el servidor nunca es visible para otros dispositivos.

En **otra** terminal, comprueba que quedó abierto a la red:

```bash
ss -ltn | grep :4000
```

Debe decir `0.0.0.0:4000`. Si dice `127.0.0.1:4000`, olvidaste `CIVIC_LAN=1`.

### 5.3 Comprueba que la tablet lo alcanza

Abre **Chrome en la tablet** y entra a `http://192.168.1.7:4000/health` (con tu IP). Debe mostrar `{"status":"ok"}`.

Si prefieres no tocar la tablet, con ella conectada por cable puedes hacer la misma petición desde su propia red (cambia la IP por la tuya):

```bash
adb shell "printf 'GET /health HTTP/1.0\r\n\r\n' | toybox nc -w 5 192.168.1.7 4000"
```

Debe empezar con `HTTP/1.0 200 OK`. Si se queda esperando y termina sin respuesta, la tablet no llega a tu computadora.

- Si no carga: revisa que estén en la misma red (paso 5.1) y que tu firewall deje pasar el puerto 4000. En Ubuntu con `ufw`: `sudo ufw allow 4000/tcp` (y `sudo ufw delete allow 4000/tcp` al terminar).

### 5.4 Corre la app apuntando a esa IP

No hace falta `adb reverse`. Por cable (para instalar) o por depuración inalámbrica:

```bash
cd app
flutter run -d HVA5KEYM --dart-define=API_URL=http://192.168.1.7:4000
```

Si cambias de red, tu IP cambia y hay que volver a compilar con la nueva.

Cuando la app ya abrió en la tablet, **puedes desconectar el cable**: queda instalada y habla con el servidor por Wi-Fi. Solo pierdes la recarga en caliente.

**Qué deberías ver.** La pantalla de bienvenida no consulta al servidor, así que verla **no prueba** que la conexión funciona. La conexión está bien cuando:

- creas una cuenta y entras al mapa (apartado 6), o
- el mapa muestra los pines y la etiqueta verde **"En vivo"** (apartado 4.7).

Si dice "No se pudo conectar con el servidor", mira el apartado 10.

> Esta forma se probó el 2026-11-11: la tablet cargó el mapa, los incidentes y el tiempo real ("En vivo") hablando con el servidor por Wi-Fi, sin puente USB. El 2026-11-12 se repitió con un hotspot de iPhone (computadora `172.20.10.6`, tablet `172.20.10.13`): la tablet alcanzó `/health` y la app se instaló apuntando a esa IP.

### 5.5 Que otras personas prueben la app (instalador APK)

Para repartir la app sin que corran `flutter run`:

```bash
cd app
flutter build apk --profile --dart-define=API_URL=http://192.168.1.7:4000
```

El instalador queda en `app/build/app/outputs/flutter-apk/app-profile.apk`. Se lo pasas a cada persona; en su teléfono tiene que permitir "instalar apps de orígenes desconocidos". Todos deben estar en la **misma red Wi-Fi** que tu computadora y con tu servidor encendido.

> Esta parte del proceso (generar el APK y que otros lo instalen) todavía **no se ha probado**. Se usa `--profile` y no `--release` porque la versión *release* exige https y bloquea las direcciones `http://`.

---

## 6. Probar el flujo de cuentas

Con el servidor y la app corriendo:

1. En la bienvenida toca **Comenzar** y luego **Regístrate**.
2. La app propone un alias al azar (`Halcon-Misti-482`). El botón **Otro** propone otro. Puedes editarlo; no uses tu nombre real.
3. Escribe una contraseña de **al menos 12 caracteres**. Una frase fácil de recordar sirve más que símbolos (el medidor mide el largo).
4. Marca la casilla de la política de privacidad y toca **Crear cuenta**. Entras al mapa.
5. El botón de la persona (a la derecha del mapa) abre tu cuenta y **Cerrar sesión**.
6. Prueba **Iniciar sesión** con el mismo alias y contraseña.
7. Cierra la app del todo y ábrela de nuevo: la sesión se conserva y entra directo al mapa.

**Cosas que conviene probar a propósito:**

- Una contraseña incorrecta: dice "Alias o contraseña incorrectos." y no revela cuál falló.
- **5 intentos fallidos seguidos** bloquean la cuenta (un minuto la primera vez; la espera se duplica si se sigue fallando, hasta 15 minutos). La app muestra una cuenta regresiva y deshabilita el botón. El aviso de bloqueo sale en el **6.º** intento.
- Apagar el servidor y abrir la app: entra al mapa con el aviso "Sin conexión: no pudimos confirmar tu sesión" y **se recupera sola** (en menos de 30 s) cuando enciendes el servidor.

### Ver qué quedó guardado

```bash
docker exec civic_db psql -U postgres -d civic_dev -c "select alias, nivel, intentos_fallidos from usuarios"
```

Lo que **nunca** se guarda en la base: contraseñas (solo su hash Argon2id), nombre, teléfono, correo ni IP.

### Borrar las cuentas de prueba

```bash
docker exec civic_db psql -U postgres -d civic_dev -c "delete from usuarios"
```

Esto borra también sus consentimientos y sesiones.

### Desbloquear una cuenta sin esperar

```bash
docker exec civic_db psql -U postgres -d civic_dev -c "update usuarios set intentos_fallidos = 0, bloqueado_hasta = null"
```

---

## 7. Datos de demostración (los pines del mapa)

El mapa solo muestra los incidentes de las **últimas 24 horas**. Los 80 incidentes que siembra `mix setup` tienen fechas repartidas en los últimos 7 días, así que **con el paso de los días van desapareciendo del mapa**: "Sin reportes en esta zona".

Para volver a tener pines:

**Opción 1: resembrar** (borra los incidentes de desarrollo y crea 80 nuevos con fechas relativas a hoy; solo una parte cae en las últimas 24 h, en la última prueba unos 30 de 80):

```bash
cd backend
mix run priv/repo/seeds.exs
```

**Opción 2: rejuvenecer los que hay**, para que los 80 queden dentro de las últimas 22 horas (útil para ver el mapa lleno):

```bash
docker exec civic_db psql -U postgres -d civic_dev -c \
  "update incidentes set inserted_at = (now() at time zone 'utc') - (random() * interval '22 hours')"
```

Para **crear un reporte tú mismo**, inicia sesión y toca **Reportar** en el mapa: se abre el formulario (tipo, ubicación y descripción). El pin nuevo aparece al instante, también en otras tablets conectadas. Hoy el servidor todavía no exige sesión para reportar; eso viene en una próxima entrega.

---

## 8. Pruebas automáticas

No necesitan la tablet ni el servidor encendido (el servidor de pruebas usa su propia base `civic_test`, que se crea sola).

| Qué | Comando | Resultado esperado hoy |
|---|---|---|
| Backend | `cd backend && mix test` | 198 tests, 0 fallos |
| App | `cd app && flutter test` | 339 tests, todos pasan |
| App: análisis | `cd app && flutter analyze` | `No issues found!` |
| App: formato | `cd app && dart format --output=none --set-exit-if-changed lib test` | sin cambios |
| Backend: todo junto antes de un commit | `cd backend && mix precommit` | compila sin avisos, formatea y pasa los tests |

Repetir la suite del backend muchas veces ayuda a cazar pruebas inestables: `mix test --repeat-until-failure 50`.

El **CI** de GitHub corre esto mismo en cada PR (el trabajo `Backend (Elixir)`, `App (Flutter)` y `Secretos (gitleaks)`). No se puede mezclar a `main` si alguno falla.

---

## 9. Apagar todo

| Qué | Cómo |
|---|---|
| Servidor | En su terminal, **Ctrl+C dos veces** |
| `flutter run` | Tecla `q` |
| La app en la tablet | Ciérrala normalmente |
| Puente USB | `adb reverse --remove-all` |
| Base de datos (conserva los datos) | `docker compose -f infra/docker-compose.yml stop` |
| Base de datos (borra todo y empieza de cero) | `docker compose -f infra/docker-compose.yml down -v` y después repite el paso 3.2 y 3.3 |

---

## 10. Problemas frecuentes

| Qué ves | Causa más probable | Qué hacer |
|---|---|---|
| La app dice **"No se pudo conectar con el servidor"** | Servidor apagado, puente USB perdido o dirección equivocada | Revisa que `curl http://127.0.0.1:4000/health` responda; repite `adb reverse tcp:4000 tcp:4000`; confirma que corriste `flutter run` con la `API_URL` correcta |
| El puente funcionaba y dejó de funcionar | `adb reverse` se pierde al desconectar el cable o reiniciar la tablet | Vuelve a ejecutar `adb reverse tcp:4000 tcp:4000` |
| `adb devices` sale vacío | Cable que solo carga, depuración USB apagada o modo de USB incorrecto | Cambia de cable o puerto; en la tablet elige "Transferencia de archivos" y activa la depuración USB |
| `adb devices` dice `unauthorized` | No aceptaste el aviso de la tablet | Mira la pantalla de la tablet y acepta "Permitir depuración" (con "Permitir siempre"). Si tiene PIN o patrón, **desbloquéala**: con la pantalla bloqueada el aviso no sale. Si aun así no aparece: desconecta y reconecta; y si sigue igual, en Opciones de desarrollador toca **"Revocar autorizaciones de depuración USB"** y vuelve a conectar el cable |
| `adb devices` dice `offline` | Conexión de `adb` colgada | `adb kill-server` y vuelve a `adb devices` |
| **Mapa gris**, sin calles | La tablet no tiene internet (los mosaicos vienen de OpenStreetMap) | Conecta la tablet a una red con internet |
| **"Sin reportes en esta zona"** | Los datos de prueba tienen más de 24 h | Mira el [apartado 7](#7-datos-de-demostración-los-pines-del-mapa) |
| **"Buscando tu ubicación…"** no termina | Permiso o GPS apagado, o estás bajo techo | Acepta el permiso de ubicación; enciende la ubicación del sistema; sal a un lugar abierto |
| El chip **"Reconectando…"** no pasa a "En vivo" | El canal en tiempo real no llega al servidor | Mismo diagnóstico que "No se pudo conectar"; confirma que el servidor sigue encendido |
| `mix phx.server` dice que el **puerto 4000 está en uso** | Quedó otro servidor corriendo | `ss -ltn \| grep 4000`; apaga el otro con `pkill -f "[p]hx\.server"` |
| `mix setup` o el servidor no encuentran la base | El contenedor está apagado | `docker compose -f infra/docker-compose.yml up -d` |
| Docker dice que el puerto **5432 ya está asignado** | Tienes otro PostgreSQL local usando ese puerto | Detén el PostgreSQL local (`sudo systemctl stop postgresql`) o cambia el puerto en `infra/docker-compose.yml` |
| **"Demasiados intentos fallidos"** | 5 contraseñas incorrectas seguidas bloquean la cuenta (1 minuto, y se duplica) | Espera la cuenta regresiva o usa el comando del [apartado 6](#6-probar-el-flujo-de-cuentas) |
| **"Hay demasiados intentos desde esta conexión"** | Límite de solicitudes por IP (en pruebas con muchas personas en la misma red) | Reinicia el servidor: los contadores viven en memoria y se reinician |
| Tras `flutter drive` la app **desapareció** de la tablet | `flutter drive` la desinstala al terminar | Vuelve a correr `flutter run` |
| Tras recompilar, **cambió la dirección** del servidor y la app sigue con la vieja | La `API_URL` se fija al compilar | Vuelve a correr `flutter run` con la nueva `--dart-define` (no basta recargar en caliente) |
| La app dice que la dirección **"debe empezar con http:// o https://"** o la rechaza | Falta el `http://` o se usó `https://` sin certificado | Usa `http://...` en desarrollo |
| En el Camino B la tablet **no carga** `http://IP:4000/health` | **Tablet y computadora en redes distintas**, red con aislamiento de clientes, firewall, servidor sin `CIVIC_LAN=1` o IP equivocada | 1) Compara las dos IP como en el [apartado 5.1](#51-confirma-que-la-tablet-y-la-computadora-están-en-la-misma-red): si los tres primeros números no coinciden, no están en la misma red. 2) `ss -ltn \| grep :4000` debe decir `0.0.0.0:4000`. 3) Vuelve a averiguar tu IP: cambia al cambiar de red. 4) Abre el puerto 4000 (`ufw`). 5) Si todo lo anterior está bien, la red aísla a los dispositivos (pasa en redes de universidad y algunos hotspots): usa otra red o el Camino A |

Si nada de esto resuelve el problema, mira los registros del servidor (la terminal de `mix phx.server`) y la salida de `flutter run`: casi siempre dicen qué falló.

---

## 11. Referencia: puertos y variables

### Puertos

| Puerto | Qué | Quién puede llegar |
|---|---|---|
| `5432` | PostgreSQL + PostGIS (contenedor `civic_db`) | Solo tu computadora (`127.0.0.1`) |
| `4000` | Servidor Phoenix | Solo tu computadora; **toda la red** con `CIVIC_LAN=1` |

### Variables que usas en desarrollo

| Variable | Dónde | Para qué |
|---|---|---|
| `API_URL` | `flutter run --dart-define=API_URL=...` | A qué servidor habla la app. Por omisión `http://10.0.2.2:4000`, la dirección de la computadora vista desde el emulador de Android |
| `CIVIC_LAN` | `CIVIC_LAN=1 mix phx.server` | Abre el servidor a la red (Camino B) |

En desarrollo **no hace falta ningún archivo `.env`**: las claves, el acceso a la base (`postgres`/`postgres`) y el secreto del servidor están en `backend/config/dev.exs` y son **solo de desarrollo**. La base solo escucha en tu computadora, así que esas credenciales no son accesibles desde fuera.

### Para un servidor en la nube (referencia)

La guía de despliegue completa queda pendiente. Estas son las variables que el servidor de producción lee en `backend/config/runtime.exs`; **ninguna se sube al repositorio** (es público):

| Variable | Para qué |
|---|---|
| `PHX_SERVER` | `true` para que el servidor arranque |
| `PHX_HOST` | El dominio público |
| `PORT` | Puerto (por omisión `4000`) |
| `DATABASE_URL` | Conexión a PostgreSQL |
| `SECRET_KEY_BASE` | Secreto del servidor (firma los tokens de acceso) |
| `CIVIC_KEY_VERIF_V1`, `CIVIC_KEY_REP_V1`, `CIVIC_KEY_VOTE_V1` | Tres claves independientes (base64 de 32 bytes cada una) para el DNI, los reportes y los votos |
| `CLIENT_IP_HEADER` | Cabecera con la IP real del cliente cuando hay un proxy delante |
| `POOL_SIZE`, `ECTO_IPV6`, `DNS_CLUSTER_QUERY` | Ajustes opcionales |

Con la nube, la app de producción **exige https** y rechaza `http://` (`usesCleartextTraffic=false`).
