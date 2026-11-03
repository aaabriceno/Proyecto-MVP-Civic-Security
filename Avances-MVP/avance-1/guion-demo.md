# Guion de la demo en vivo — Avance 1

Todos los datos de la demo son **ficticios**, generados por `backend/priv/repo/seeds.exs`.

## Antes de clase (5 min)

```bash
cd ~/"Documentos/Semestre 2026-2/Proyecto-Civic-Security-MVP"
docker compose -f infra/docker-compose.yml up -d          # base de datos
cd backend && mix run priv/repo/seeds.exs                 # 80 reportes ficticios
mix run priv/repo/demo_mapa.exs && cd ..                  # genera el mapa
```

Sirve el mapa desde un servidor local, en **otra terminal** que se queda abierta:

```bash
python3 -m http.server 8000 --bind 127.0.0.1 -d Avances-MVP/avance-1
```

Abre <http://localhost:8000/mapa-demo.html> una vez para que se carguen las teselas (necesita internet). **No lo abras con doble clic:** como archivo (`file://`) el navegador no envía *Referer* y OpenStreetMap responde "403 Access blocked".

Agranda la fuente de la terminal (`Ctrl` + `+`) para que se lea en el proyector.

## Durante la demo (~5 min)

### 1. La infraestructura está arriba
```bash
docker compose -f infra/docker-compose.yml ps
```
> "La base de datos PostgreSQL con PostGIS corre en Docker. Solo acepta conexiones desde esta laptop (127.0.0.1)."

### 2. Las reglas de negocio funcionan (pruebas automáticas)
```bash
cd backend && mix test --trace test/civic && cd ..
```
> "Estas 7 pruebas verifican las reglas: solo 5 tipos de incidente, solo reportes dentro de Arequipa, máximo 500 caracteres y sin duplicados si la app reintenta."

### 3. Generamos reportes ficticios pasando por esas reglas
```bash
cd backend && mix run priv/repo/seeds.exs && cd ..
```
> "Creamos 80 reportes en 12 zonas de Arequipa. Al final se ve que el sistema rechaza un reporte en Lima, un tipo inventado y un envío duplicado."

### 4. Qué podemos consultar con estos datos
```bash
docker compose -f infra/docker-compose.yml exec -T db psql -U postgres -d civic_dev < backend/priv/repo/demo_consultas.sql
```
Puntos para comentar (sube con la rueda del mouse):

| Consulta | Qué decir |
|---|---|
| 1–2 | Reportes por tipo y por estado de la validación comunitaria |
| 3 | Los filtros del mapa: última hora, 24 h y 7 días |
| 4 | **PostGIS** calcula distancias reales en metros: es la base de la regla "3 votos a menos de 1 km" |
| 5 | **Mapa de calor**: agrupa los reportes en celdas de ~500 m |
| 6 | Horas de mayor riesgo: se concentran en la noche |
| 7 | Lo que mostrará el mapa en pantalla según el área visible |
| 8 | **Anonimato:** ninguna columna identifica a quien reporta |
| 9–10 | La base de datos rechaza duplicados y textos largos aunque el código fallara (defensa en profundidad) |

### 5. El mapa
Abre <http://localhost:8000/mapa-demo.html> (`F11` para pantalla completa).
- Pines verdes, naranjas y grises: verificado, sin verificar, descartado. Haz clic en uno para ver su detalle.
- Activa **"Mapa de calor"** en la esquina superior derecha.
- El círculo azul es el radio de 1 km de votación alrededor de la UCSP.

> "Esto es lo que la app Flutter mostrará en el teléfono en el siguiente avance. Hoy lo generamos directamente desde la base de datos."

### 6. Cierre
> "Siguiente avance: la API REST (`POST /v1/incidents`, `GET /v1/map/snapshot`), el canal en tiempo real y la app Android que consume estos datos."

## Si algo falla
- `connection refused` → la base está apagada: `docker compose -f infra/docker-compose.yml start`
- El mapa muestra "403 Access blocked" → lo abriste como archivo; usa <http://localhost:8000/mapa-demo.html>.
- El mapa no carga el fondo → no hay internet. Muestra las consultas SQL; los pines necesitan las teselas de OSM.
- Para volver a empezar desde cero: correr de nuevo `seeds.exs`, que borra los datos ficticios y los recrea iguales.
