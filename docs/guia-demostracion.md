# Guía de demostración

Qué ejecutar, en qué orden y qué hacer si algo falla el día de la presentación. Todo se hace desde **la laptop que corre el servidor**. Los pasos de instalación de la app y de red explican más en la [guía de ejecución local](guia-ejecucion-local.md).

## Contenido

1. [Antes de salir](#1-antes-de-salir)
2. [Levantar todo](#2-levantar-todo)
3. [Conectar los dispositivos a tu red](#3-conectar-los-dispositivos-a-tu-red)
4. [Instalar la app en otros celulares: por cable](#4-instalar-la-app-en-otros-celulares-por-cable)
5. [Instalar la app sin cable](#5-instalar-la-app-sin-cable)
6. [Probar el flujo completo](#6-probar-el-flujo-completo)
7. [Datos de la demostración](#7-datos-de-la-demostración)
8. [Correr las pruebas automáticas](#8-correr-las-pruebas-automáticas)
9. [Emulador de la laptop](#9-emulador-de-la-laptop)
10. [Si algo falla](#10-si-algo-falla)

Todos los comandos se escriben **desde la carpeta del proyecto** salvo que se indique otra cosa.

---

## 1. Antes de salir

- [ ] Laptop **con el cargador** y con la suspensión desactivada (si se duerme, el servidor deja de atender): Configuración → Energía → *Suspensión automática: Nunca*, y tapa cerrada = no hacer nada.
- [ ] El APK está en `~/civic-demo/civic-security.apk` (si no, ver [Recompilar el APK](#recompilar-el-apk)).
- [ ] La base de datos arranca (`docker ps` muestra `civic_db` en *healthy*).
- [ ] Cables USB-C / micro-USB para los celulares de tus compañeros.
- [ ] Probaste **una vez** con el hotspot de tu celular: laptop, tablet y un teléfono más.

---

## 2. Levantar todo

En una terminal:

```bash
# 1. Base de datos (conserva los datos)
docker start civic_db            # o: docker compose -f infra/docker-compose.yml up -d

# 2. Servidor, abierto a la red
cd backend
CIVIC_LAN=1 mix phx.server
```

Para ver el **cambio de estado** con pocos dispositivos, baja el umbral de votos (por omisión 3):

```bash
CIVIC_LAN=1 CIVIC_VOTE_THRESHOLD=2 mix phx.server
```

Comprueba en **otra** terminal:

```bash
curl http://127.0.0.1:4000/health        # {"status":"ok"}
ss -ltn | grep :4000                     # debe decir 0.0.0.0:4000
```

> Si cambias algo de `config/` o de las dependencias (`mix.lock`) con el servidor encendido, **reinícialo** (Ctrl+C dos veces y vuelve a lanzarlo): mientras tanto responde con un error de compilación.

Apagar: **Ctrl+C dos veces** en la terminal del servidor.

---

## 3. Conectar los dispositivos a tu red

Todos (laptop, tablet, celulares) tienen que estar en la **misma red Wi-Fi**; en la presentación, el hotspot de tu celular.

1. Conecta la laptop al Wi-Fi del hotspot.
2. Averigua la IP de la laptop **en esa red** (cambia cada vez que te conectas):

   ```bash
   ip -4 route get 1.1.1.1 | grep -o 'src [0-9.]*'
   ```

   Un hotspot de iPhone da `172.20.10.x`; los de Android suelen dar `192.168.43.x` u otro rango.
3. En **cada** dispositivo, en la pantalla de bienvenida de la app: **Servidor: … · Cambiar** → escribe esa IP (basta `172.20.10.14`) → **Probar** (debe decir *"El servidor responde"*) → **Guardar**.

Guardar cierra la sesión de ese dispositivo: vuelve a entrar con tu cuenta.

El mapa necesita internet para descargar sus cuadritos: el hotspot lo da con los datos del celular.

**Plan B si la red no deja que los dispositivos se hablen** (pasa en redes de universidad): conecta la tablet por cable, `adb reverse tcp:4000 tcp:4000`, y en la app pon el servidor `127.0.0.1:4000`.

---

## 4. Instalar la app en otros celulares: por cable

Sirve para celulares Android (no iPhone). El instalador es `~/civic-demo/civic-security.apk` y pesa unos 85 MB.

**Una sola vez, en la laptop:**

```bash
export PATH=$PATH:$HOME/Android/Sdk/platform-tools     # para usar `adb`
adb version                                            # debe responder
```

**En el celular de tu compañero** (Android 7 o más nuevo):

1. Ajustes → **Acerca del teléfono** → toca 7 veces **Número de compilación** (te dice "ya eres desarrollador").
2. Ajustes → **Opciones de desarrollador** → activa **Depuración por USB**. En Xiaomi/Redmi/Poco activa también **Instalar mediante USB**.
3. Conéctalo a la laptop con el cable (que sea de datos, no solo de carga). Si pregunta el modo USB, elige **Transferencia de archivos**.
4. Desbloquea el celular y acepta **"¿Permitir la depuración por USB?"** (marca *Permitir siempre*).

**En la laptop:**

```bash
adb devices
```

Debe aparecer el celular con la palabra **`device`** (si dice `unauthorized`, acepta el aviso en el celular; si no aparece, otro cable u otro puerto).

```bash
# Un solo celular conectado:
adb install -r ~/civic-demo/civic-security.apk

# Varios a la vez (usa el número de serie de `adb devices`):
adb -s NUMERO_DE_SERIE install -r ~/civic-demo/civic-security.apk

# Todos los conectados, de una vez:
for s in $(adb devices | awk 'NR>1 && $2=="device"{print $1}'); do
  adb -s "$s" install -r ~/civic-demo/civic-security.apk
done
```

Debe responder **`Success`**. Después, en el celular: abre **Civic Security**, acepta el permiso de ubicación (*Mientras se usa la app*) y pon la IP del servidor (ver [apartado 3](#3-conectar-los-dispositivos-a-tu-red)).

**Si falla la instalación:**

| Mensaje | Qué hacer |
|---|---|
| `INSTALL_FAILED_UPDATE_INCOMPATIBLE` | Ya hay otra versión firmada distinto: `adb uninstall pe.civicsecurity.civic_security` y repite la instalación |
| `INSTALL_FAILED_USER_RESTRICTED` | Falta **Instalar mediante USB** (Xiaomi/Redmi/Poco) o aceptar el cuadro de instalación en la pantalla del celular (Oppo, Vivo, Realme) |
| Aviso de **Google Play Protect** ("aplicación no verificada") | Es normal con un APK de prueba: **Instalar de todos modos** |
| `device unauthorized` | Mira la pantalla del celular y acepta la depuración |
| `no devices/emulators found` | Cable que solo carga, depuración apagada o `adb kill-server` y repetir |

### Recompilar el APK

Solo si cambió el código. La IP con la que se compila es la **de fábrica**; después se cambia desde la app, así que no hace falta recompilar al cambiar de red.

```bash
cd app
flutter build apk --profile --dart-define=API_URL=http://192.168.1.7:4000
cp build/app/outputs/flutter-apk/app-profile.apk ~/civic-demo/civic-security.apk
```

Se usa `--profile` y no `--release` porque la versión *release* exige https.

---

## 5. Instalar la app sin cable

Con la laptop como servidor de descargas (todos en la misma red):

```bash
cd ~/civic-demo
python3 -m http.server 8000
```

En el navegador del celular: `http://IP_DE_LA_LAPTOP:8000/civic-security.apk`. Permite *instalar apps de orígenes desconocidos* al navegador cuando Android lo pida, y acepta el aviso de Play Protect. Pesa unos 85 MB; por el hotspot local no gasta los datos del celular.

Para detenerlo: Ctrl+C.

---

## 6. Probar el flujo completo

1. Cada dispositivo crea **su propia cuenta** (alias que sugiere la app) y la **verifica con un DNI distinto** de 8 dígitos: Perfil → *Verifica tu DNI*. Para ensayar usa números inventados, no tu DNI real.
2. Un dispositivo **reporta** (botón *Reportar*; puede agregar foto). Los demás ven el pin **en vivo**, con la foto.
3. Los demás abren el reporte y pulsan **Lo confirmo** o **Es falso**. El autor no puede votar el suyo. Hay que estar a menos de 1 km del lugar.
4. Con 3 confirmaciones (2 si arrancaste con `CIVIC_VOTE_THRESHOLD=2`) pasa a **Verificado**; con 3 "Es falso", a **Descartado**. Todos lo ven al instante.

Los teléfonos virtuales hay que ponerlos cerca del reporte ([apartado 9](#9-emulador-de-la-laptop)).

---

## 7. Datos de la demostración

> **No corras `mix run priv/repo/seeds.exs`.** Ese script ejecuta `Repo.delete_all(Incident)`: **borra todos los reportes, también los reales**, y crea 80 ficticios.

Ver qué hay:

```bash
docker exec civic_db psql -U postgres -d civic_dev -c \
  "select left(id::text,8) id, tipo, estado, confirmaciones c, falsos f, tiene_foto foto, left(descripcion,40) from incidentes order by inserted_at"
docker exec civic_db psql -U postgres -d civic_dev -c "select alias, nivel from usuarios order by inserted_at"
```

El mapa solo muestra los reportes de las **últimas 24 horas**: lo creado hace más de un día no se ve, aunque siga en la base. Para la demostración, crea reportes nuevos desde los dispositivos.

Borrar **solo los ficticios** (los de la siembra no tienen autor):

```bash
docker exec -i civic_db psql -U postgres -d civic_dev -c "delete from incidentes where reporter_token is null"
```

Borrar un reporte de prueba concreto (sus votos se borran solos):

```bash
docker exec -i civic_db psql -U postgres -d civic_dev -c "delete from incidentes where id = 'UUID_COMPLETO'"
```

Borrar una cuenta de prueba (libera su DNI):

```bash
docker exec -i civic_db psql -U postgres -d civic_dev -c "delete from usuarios where alias = 'ALIAS'"
```

Las fotos se guardan en `backend/priv/uploads/<id-del-reporte>.jpg`; si borras un reporte, puedes borrar su archivo a mano.

---

## 8. Correr las pruebas automáticas

```bash
# Servidor (crea y migra la base de pruebas sola)
cd backend
mix test                  # todas
mix precommit             # compila sin avisos, da formato y corre las pruebas
mix sobelow --exit --skip # análisis de seguridad
mix hex.audit             # paquetes con avisos de seguridad
mix deps.audit            # vulnerabilidades en dependencias

# App
cd ../app
flutter analyze
flutter test
dart format --output=none --set-exit-if-changed lib test
```

Son las mismas comprobaciones que corre el CI de GitHub en cada PR.

---

## 9. Emulador de la laptop

Es un teléfono Android virtual (Pixel 9 Pro XL) para tener un segundo dispositivo en la mesa.

```bash
# Abrirlo (déjalo abierto; no lo cierres si no hace falta)
~/Android/Sdk/emulator/emulator -avd Pixel_9_Pro_XL -no-audio

# Instalar o actualizar la app
adb -s emulator-5554 install -r ~/civic-demo/civic-security.apk

# Su ubicación (longitud primero, luego latitud) y encender la ubicación del sistema
adb -s emulator-5554 emu geo fix -71.5172 -16.3750
adb -s emulator-5554 shell cmd location set-location-enabled true
```

- Desde el emulador, el servidor de esta laptop es **`10.0.2.2:4000`** (o la IP de la red; ambas sirven).
- Para votar, el emulador debe estar a menos de 1 km del reporte: pon su ubicación cerca de donde reporta el otro dispositivo.
- La primera vez Google muestra un aviso de *Location Accuracy*: **Turn on**.
- **Si lo cierras y lo vuelves a abrir** y la app ya no está, reinstálala con el comando de arriba (el emulador restaura una foto antigua de su estado). Para guardar el estado actual: `adb -s emulator-5554 emu avd snapshot save default_boot`.
- Si el mapa del emulador se queda gris, su red se degradó: reiniciarlo y reinstalar la app lo arregla.

---

## 10. Si algo falla

| Qué ves | Qué hacer |
|---|---|
| La app dice **"No se pudo conectar con el servidor"** | `curl http://127.0.0.1:4000/health` en la laptop; si falla, relanza el servidor. Si responde, revisa la IP en *Servidor: … Cambiar* → **Probar** |
| **Probar** dice que no responde | Dispositivo y laptop en **redes distintas**; servidor sin `CIVIC_LAN=1` (`ss -ltn \| grep :4000` debe decir `0.0.0.0:4000`); IP equivocada (cambia en cada red); o el firewall de la laptop: `sudo ufw allow 4000/tcp` |
| El servidor responde con un **error de compilación** en HTML | Cambiaste `config/` o `mix.lock` con el servidor encendido: reinícialo |
| El chip **"Reconectando…"** no pasa a *En vivo* | El servidor se cayó o la red perdió al dispositivo; mira la terminal del servidor |
| **"Sin reportes en esta zona"** | Los reportes tienen más de 24 h: crea uno nuevo ([apartado 7](#7-datos-de-la-demostración)) |
| Al votar: **"Verifica tu cuenta con el DNI"** | Perfil → *Verifica tu DNI* |
| Al votar: **"Tienes que estar cerca del lugar"** | El GPS del dispositivo está a más de 1 km del reporte (en un emulador, [ponle otra ubicación](#9-emulador-de-la-laptop)); en una emergencia arranca con `CIVIC_VOTE_RADIUS_M=5000` |
| Al votar: **"No puedes votar tu propio reporte"** | Vota desde otro dispositivo |
| **"Este DNI ya tiene una cuenta"** | Ese número ya lo usó otra cuenta: usa otro |
| Mapa **gris** o a pedazos | Internet lento o inestable: el mapa descarga cuadritos de OpenStreetMap. Prueba con otra red; si es un emulador, reinícialo |
| `adb devices` vacío o `unauthorized` | Ver [apartado 4](#4-instalar-la-app-en-otros-celulares-por-cable) |
