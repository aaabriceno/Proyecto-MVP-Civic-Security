# Comandos explicados

Cada comando: **qué hace** y **para qué sirve**. Los que tienen varias partes se desarman en una tabla.

Se ejecutan en la **laptop del servidor**, en una terminal, salvo la sección de Windows.

## Levantar el servidor: secuencia completa

Copia y pega, en este orden. Cada línea se explica más abajo (secciones 0 a 3).

**Terminal 1: base de datos y servidor** (esta terminal queda ocupada por el servidor):

```bash
cd "$HOME/Documentos/Semestre 2026-2/Proyecto-Civic-Security-MVP"
docker start civic_db
docker ps
cd backend
CIVIC_LAN=1 mix phx.server
```

Espera a ver `Running CivicWeb.Endpoint with Bandit ... at 0.0.0.0:4000`. Si quieres ver el cambio de estado de un reporte con pocos dispositivos, la última línea es:

```bash
CIVIC_LAN=1 CIVIC_VOTE_THRESHOLD=2 mix phx.server
```

**Terminal 2: comprobar** (ábrela con `Ctrl+Alt+T`):

```bash
curl http://127.0.0.1:4000/health
ss -ltn | grep :4000
ip -4 route get 1.1.1.1 | grep -o 'src [0-9.]*'
```

| Debe salir | Qué significa |
|---|---|
| `{"status":"ok"}` | El servidor responde |
| `... 0.0.0.0:4000 ...` | Está abierto a la red (si dice `127.0.0.1:4000`, falta `CIVIC_LAN=1`) |
| `src 172.20.10.14` | Esa es la IP que se escribe en la app (**Cambiar**) |

**Si dice `address already in use`** (ya hay un servidor en el puerto 4000):

```bash
ss -ltnp | grep :4000        # al final aparece pid=NUMERO
kill NUMERO                  # lo apaga; luego repite el arranque
```

**Apagar todo** (en este orden):

```bash
# Terminal 1: Ctrl+C dos veces
docker stop civic_db
adb reverse --remove-all     # solo si usaste el puente USB
```

---

## Contenido

0. [Ir a la carpeta del proyecto](#0-ir-a-la-carpeta-del-proyecto)
1. [Base de datos](#1-base-de-datos)
2. [Servidor](#2-servidor)
3. [Red e IP](#3-red-e-ip)
4. [Pruebas automáticas](#4-pruebas-automáticas)
5. [Compilar el APK](#5-compilar-el-apk)
6. [Instalar el APK por cable (`adb`)](#6-instalar-el-apk-por-cable-adb)
7. [Instalar el APK sin cable](#7-instalar-el-apk-sin-cable)
8. [Emulador de la laptop](#8-emulador-de-la-laptop)
9. [Datos (consultas a la base)](#9-datos-consultas-a-la-base)
10. [Git](#10-git)
11. [PC grande con Windows](#11-pc-grande-con-windows)

---

## 0. Ir a la carpeta del proyecto

```bash
cd "$HOME/Documentos/Semestre 2026-2/Proyecto-Civic-Security-MVP"
```

| Parte | Qué es |
|---|---|
| `cd` | Cambiar de carpeta |
| `"$HOME/..."` | `$HOME` es tu carpeta personal. Las comillas hacen falta porque la ruta tiene un espacio |

**Para qué:** todos los demás comandos parten de aquí.

---

## 1. Base de datos

| Comando | Qué hace | Para qué |
|---|---|---|
| `docker start civic_db` | Enciende el contenedor de la base de datos (conserva los datos) | Antes de arrancar el servidor |
| `docker ps` | Lista los contenedores encendidos | Comprobar que `civic_db` dice `healthy` |
| `docker stop civic_db` | Apaga la base de datos | Al terminar |
| `docker compose -f infra/docker-compose.yml up -d` | Crea y enciende la base según el archivo `infra/docker-compose.yml` (`-d` = en segundo plano) | Alternativa a `docker start`, o si el contenedor no existe |

---

## 2. Servidor

```bash
cd backend
CIVIC_LAN=1 mix phx.server
```

| Parte | Qué es |
|---|---|
| `cd backend` | Entra a la carpeta del servidor |
| `CIVIC_LAN=1` | Variable solo para este comando: el servidor escucha en **toda la red**, no solo en tu laptop. Sin ella, ningún otro dispositivo lo ve |
| `mix phx.server` | Arranca el servidor (Elixir/Phoenix) en el puerto 4000 |

**Variables opcionales** (se escriben delante, igual que `CIVIC_LAN=1`):

| Variable | Qué cambia | Por omisión |
|---|---|---|
| `CIVIC_VOTE_THRESHOLD=2` | Cuántos votos iguales hacen falta para pasar a *Verificado* o *Descartado* | 3 |
| `CIVIC_VOTE_RADIUS_M=5000` | A cuántos metros del reporte hay que estar para votar | 1000 |
| `CIVIC_CUPO_SIN_VERIFICAR=50` | Reportes por día de una cuenta sin verificar | 3 |
| `CIVIC_CUPO_VERIFICADO=50` | Reportes por día de una cuenta verificada | 10 |

Ejemplo con varias: `CIVIC_LAN=1 CIVIC_VOTE_THRESHOLD=2 mix phx.server`

**Comprobar que funciona** (en otra terminal):

| Comando | Qué hace | Para qué |
|---|---|---|
| `curl http://127.0.0.1:4000/health` | Pide al servidor su estado | Debe responder `{"status":"ok"}` |
| `ss -ltn \| grep :4000` | `ss` lista conexiones; `-l` solo las que esperan, `-t` TCP, `-n` con números; `grep :4000` deja la línea del puerto 4000 | Debe decir `0.0.0.0:4000` (abierto a la red). Si dice `127.0.0.1:4000`, falta `CIVIC_LAN=1` |

**Apagar:** `Ctrl+C` dos veces en la terminal del servidor.

> Si cambias `config/` o `mix.lock` con el servidor encendido, apágalo y vuélvelo a arrancar: mientras tanto responde con un error de compilación.

---

## 3. Red e IP

```bash
ip -4 route get 1.1.1.1 | grep -o 'src [0-9.]*'
```

| Parte | Qué es |
|---|---|
| `ip -4` | Herramienta de red, solo direcciones IPv4 |
| `route get 1.1.1.1` | Pregunta por qué conexión saldría tu laptop a internet (`1.1.1.1` es solo un destino cualquiera) |
| `\|` | Pasa la salida al siguiente comando |
| `grep -o 'src [0-9.]*'` | Se queda solo con la parte `src` + IP (`-o` = solo lo que coincide) |

**Qué da:** `src 172.20.10.14` → esa es **la IP de tu laptop en la red actual**. Es la que se escribe en la app (**Cambiar**). Cambia cada vez que te conectas a otra red.

| Comando | Qué hace | Para qué |
|---|---|---|
| `sudo ufw allow 4000/tcp` | Abre el puerto 4000 en el firewall | Si los dispositivos no llegan al servidor |
| `sudo ufw delete allow 4000/tcp` | Vuelve a cerrarlo | Al terminar |

---

## 4. Pruebas automáticas

### Servidor (`cd backend`)

| Comando | Qué hace | Para qué |
|---|---|---|
| `mix test` | Corre todas las pruebas (crea y migra la base de pruebas sola) | Comprobar que nada se rompió |
| `mix precommit` | Compila sin avisos, borra dependencias sobrantes, da formato y corre las pruebas | Revisión completa antes de subir cambios |
| `mix format --check-formatted` | Revisa el formato del código **sin cambiarlo** | Lo exige el CI |
| `mix compile --warnings-as-errors` | Compila y trata cada aviso como error | Lo exige el CI |
| `mix deps.unlock --check-unused` | Detecta dependencias que sobran en `mix.lock` | Lo exige el CI |
| `mix sobelow --exit --skip` | Busca fallos de seguridad en el código. `--exit` falla si encuentra algo; `--skip` respeta las excepciones marcadas en el código | Seguridad (CI) |
| `mix deps.audit` | Compara las dependencias con una lista de vulnerabilidades conocidas | Seguridad (CI) |
| `mix hex.audit` | Avisa de paquetes retirados o con alertas de seguridad | Seguridad (CI) |

### App (`cd app`)

| Comando | Qué hace | Para qué |
|---|---|---|
| `flutter analyze` | Análisis estático: errores y malas prácticas | Lo exige el CI |
| `flutter test` | Corre todas las pruebas de la app | Lo exige el CI |
| `dart format --output=none --set-exit-if-changed lib test` | Revisa el formato sin escribir nada (`--set-exit-if-changed` falla si algo cambiaría) | Lo exige el CI |

---

## 5. Compilar el APK

Solo si cambió el código de la app.

```bash
cd app
flutter build apk --profile --dart-define=API_URL=http://192.168.1.7:4000
cp build/app/outputs/flutter-apk/app-profile.apk ~/civic-demo/civic-security.apk
```

| Parte | Qué es |
|---|---|
| `flutter build apk` | Genera el instalador `.apk` |
| `--profile` | Modo de prueba. No se usa `--release` porque esa versión exige `https` y bloquea nuestra red local `http` |
| `--dart-define=API_URL=...` | Dirección del servidor **de fábrica**. Después se cambia desde la app (**Cambiar**), no hace falta recompilar |
| `cp A B` | Copia el archivo `A` a `B` |
| `build/app/outputs/flutter-apk/app-profile.apk` | Dónde deja Flutter el instalador |
| `~/civic-demo/civic-security.apk` | La copia que se reparte (la carpeta que sirve el [apartado 7](#7-instalar-el-apk-sin-cable)) |

---

## 6. Instalar el APK por cable (`adb`)

`adb` es la herramienta de Android que habla con un celular conectado por USB. El celular necesita **Depuración por USB** activada (Ajustes → Acerca del teléfono → 7 toques en *Número de compilación* → Opciones de desarrollador).

| Comando | Qué hace | Para qué |
|---|---|---|
| `export PATH=$PATH:$HOME/Android/Sdk/platform-tools` | Agrega la carpeta de `adb` a los programas que la terminal conoce (solo esa terminal) | Poder escribir `adb` |
| `adb version` | Muestra la versión | Comprobar que `adb` funciona |
| `adb devices` | Lista los dispositivos conectados | Debe decir **`device`**. `unauthorized` = acepta el aviso en el celular. `offline` = reconecta |
| `adb install -r ~/civic-demo/civic-security.apk` | Instala el APK. `-r` reinstala **conservando los datos** (la cuenta) | Instalar o actualizar en **un** celular |
| `adb -s NUMERO_DE_SERIE install -r ~/civic-demo/civic-security.apk` | Igual, pero en el celular que elijas con `-s` | Cuando hay **varios** conectados |
| `adb uninstall pe.civicsecurity.civic_security` | Desinstala la app | Si la instalación da `INSTALL_FAILED_UPDATE_INCOMPATIBLE` |
| `adb kill-server` | Reinicia el programa de fondo de `adb` | Si `adb devices` sale vacío o colgado |
| `adb reverse tcp:4000 tcp:4000` | Hace que el `localhost:4000` **del celular** llegue al `:4000` de la laptop | Plan B por cable, sin red. En la app: servidor `127.0.0.1:4000` |
| `adb reverse --remove-all` | Quita ese puente | Al terminar |

**Instalar en todos los celulares conectados, de una vez:**

```bash
for s in $(adb devices | awk 'NR>1 && $2=="device"{print $1}'); do
  adb -s "$s" install -r ~/civic-demo/civic-security.apk
done
```

| Parte | Qué es |
|---|---|
| `adb devices` | Lista dispositivos (primera línea es un título; luego una por celular: `serie  estado`) |
| `awk '...'` | Filtra esa lista |
| `NR>1` | Salta la primera línea (el título) |
| `$2=="device"` | Solo los que están en estado `device` (listos) |
| `{print $1}` | Imprime la primera columna: el número de serie |
| `$( ... )` | Usa esa salida como resultado |
| `for s in ...; do ... done` | Repite lo de adentro, una vez por cada número de serie (`s`) |
| `adb -s "$s" install -r ...` | Instala en ese celular |

**Después, en cada celular:** abre la app → acepta la ubicación → en la bienvenida, **Cambiar** → escribe la IP de la laptop → **Probar** → **Guardar**.

---

## 7. Instalar el APK sin cable

```bash
cd ~/civic-demo
python3 -m http.server 8000
```

| Parte | Qué es |
|---|---|
| `cd ~/civic-demo` | Entra a la carpeta donde está el APK |
| `python3 -m http.server 8000` | Convierte esa carpeta en una página web sencilla en el puerto 8000 |

**Para qué:** en el navegador del celular se abre `http://IP_DE_LA_LAPTOP:8000/civic-security.apk` y se descarga. Misma red Wi-Fi. Detener con `Ctrl+C`.

---

## 8. Emulador de la laptop

| Comando | Qué hace | Para qué |
|---|---|---|
| `~/Android/Sdk/emulator/emulator -avd Pixel_9_Pro_XL -no-audio` | Abre el teléfono virtual (`-avd` = nombre del teléfono; `-no-audio` = sin sonido) | Tener un segundo dispositivo |
| `adb -s emulator-5554 install -r ~/civic-demo/civic-security.apk` | Instala la app en el emulador (`emulator-5554` es su nombre) | Si la app no está |
| `adb -s emulator-5554 emu geo fix -71.5172 -16.3750` | Pone el GPS del emulador. **Primero longitud, luego latitud** | Estar cerca del reporte (< 1 km) y dentro de Arequipa |
| `adb -s emulator-5554 shell cmd location set-location-enabled true` | Enciende la ubicación del sistema | Si dice "No pudimos obtener tu ubicación" |
| `adb -s emulator-5554 emu avd snapshot save default_boot` | Guarda el estado actual del emulador | Para que no pierda la app si se reinicia |
| `adb -s emulator-5554 emu kill` | Cierra el emulador | Reiniciarlo si el mapa se queda gris |

En el emulador, el servidor de la laptop es **`10.0.2.2:4000`**.

---

## 9. Datos (consultas a la base)

Todas usan este molde:

```bash
docker exec -i civic_db psql -U postgres -d civic_dev -c "CONSULTA"
```

| Parte | Qué es |
|---|---|
| `docker exec -i civic_db` | Ejecuta algo **dentro** del contenedor `civic_db` (`-i` deja pasar el texto) |
| `psql` | El programa para hablar con la base de datos |
| `-U postgres` | Con el usuario `postgres` |
| `-d civic_dev` | En la base `civic_dev` (la de desarrollo) |
| `-c "..."` | Ejecuta esa consulta SQL y termina |

| Consulta (`CONSULTA`) | Qué hace |
|---|---|
| `select left(id::text,8) id, tipo, estado, confirmaciones c, falsos f, tiene_foto foto, left(descripcion,40) from incidentes order by inserted_at` | Lista los reportes (id corto, tipo, estado, votos, si tiene foto, descripción) |
| `select alias, nivel from usuarios order by inserted_at` | Lista las cuentas y si están verificadas |
| `delete from incidentes where reporter_token is null` | Borra los reportes **sin autor** (los ficticios de la siembra). Los reales tienen autor y no se tocan |
| `delete from incidentes where id = 'UUID_COMPLETO'` | Borra un reporte concreto (sus votos se borran solos) |
| `delete from usuarios where alias = 'ALIAS'` | Borra una cuenta y libera su DNI |

> **Nunca corras `mix run priv/repo/seeds.exs`:** borra **todos** los reportes, también los reales.

El mapa solo muestra reportes de las **últimas 24 horas**.

---

## 10. Git

| Comando | Qué hace | Para qué |
|---|---|---|
| `git status` | Muestra qué archivos cambiaron | Ver si hay cambios sin guardar |
| `git log --oneline -5` | Los últimos 5 cambios guardados, una línea cada uno | Ver en qué versión estás |
| `git checkout main` | Cambia a la rama principal | Volver a la versión oficial |
| `git pull` | Trae los cambios nuevos de GitHub | Actualizar el código |

---

## 11. PC grande con Windows

PowerShell **como administrador**:

| Comando | Qué hace | Para qué |
|---|---|---|
| `Enable-WindowsOptionalFeature -Online -FeatureName HypervisorPlatform -All` | Activa la *Plataforma del hipervisor de Windows* | Que el emulador de Android use la virtualización |
| `Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -All` | Activa la *Plataforma de máquina virtual* | Idem |
| `cd $env:LOCALAPPDATA\Android\Sdk\emulator` | Entra a la carpeta del emulador | Para el siguiente comando |
| `.\emulator.exe -accel-check` | Comprueba si hay aceleración por hardware | Debe decir *"WHPX ... is installed and usable"* |

Requisito previo: **virtualización activada en la BIOS** (Intel VT-x o AMD SVM Mode).
