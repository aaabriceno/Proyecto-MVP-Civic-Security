-- Consultas de demostración del avance 1 (datos ficticios de seeds.exs).
--
-- Desde la raíz del repo:
--   docker compose -f infra/docker-compose.yml exec -T db psql -U postgres -d civic_dev < backend/priv/repo/demo_consultas.sql

\set QUIET on
\pset border 2

\echo
\echo '=== 1. Reportes por tipo de incidente ==='
SELECT tipo, count(*) AS reportes
FROM incidentes
GROUP BY tipo
ORDER BY reportes DESC;

\echo
\echo '=== 2. Estado de la validación comunitaria ==='
SELECT estado, count(*) AS reportes
FROM incidentes
GROUP BY estado
ORDER BY reportes DESC;

\echo
\echo '=== 3. Filtros de tiempo del mapa (última hora, 24 h, 7 días) ==='
SELECT
  count(*) FILTER (WHERE inserted_at > (now() AT TIME ZONE 'UTC') - interval '1 hour')  AS ultima_hora,
  count(*) FILTER (WHERE inserted_at > (now() AT TIME ZONE 'UTC') - interval '24 hours') AS ultimas_24h,
  count(*) FILTER (WHERE inserted_at > (now() AT TIME ZONE 'UTC') - interval '7 days')   AS ultimos_7_dias
FROM incidentes;

\echo
\echo '=== 4. Reportes a menos de 1 km de la UCSP (base de la regla de votos) ==='
SELECT
  tipo,
  estado,
  round(ST_Distance(ubicacion, ST_MakePoint(-71.5340, -16.3963)::geography)) AS metros,
  to_char(inserted_at AT TIME ZONE 'UTC' AT TIME ZONE 'America/Lima', 'DD/MM HH24:MI') AS hora_lima
FROM incidentes
WHERE ST_DWithin(ubicacion, ST_MakePoint(-71.5340, -16.3963)::geography, 1000)
ORDER BY metros
LIMIT 12;

\echo
\echo '=== 5. Mapa de calor: zonas de ~500 m con más reportes (sin contar descartados) ==='
SELECT
  round(ST_Y(celda)::numeric, 3) AS lat,
  round(ST_X(celda)::numeric, 3) AS lng,
  count(*) AS reportes,
  repeat('#', count(*)::int) AS intensidad
FROM (
  SELECT ST_SnapToGrid(ubicacion::geometry, 0.005) AS celda
  FROM incidentes
  WHERE estado <> 'descartado'
) AS t
GROUP BY celda
ORDER BY reportes DESC
LIMIT 8;

\echo
\echo '=== 6. Franja horaria con más reportes (hora de Lima) ==='
SELECT
  extract(hour FROM inserted_at AT TIME ZONE 'UTC' AT TIME ZONE 'America/Lima')::int AS hora,
  count(*) AS reportes,
  repeat('#', count(*)::int) AS grafico
FROM incidentes
GROUP BY hora
ORDER BY hora;

\echo
\echo '=== 7. Lo que verá el mapa en pantalla: reportes dentro del área visible (centro de Arequipa) ==='
SELECT count(*) AS reportes_en_pantalla
FROM incidentes
WHERE ST_Intersects(
  ubicacion,
  ST_MakeEnvelope(-71.545, -16.405, -71.525, -16.390, 4326)::geography
);

\echo
\echo '=== 8. Anonimato: columnas de la tabla (ninguna identifica al usuario) ==='
SELECT column_name, udt_name AS tipo_de_dato
FROM information_schema.columns
WHERE table_name = 'incidentes'
ORDER BY ordinal_position;

\echo
\echo '=== 9. La base de datos rechaza un reporte duplicado (debe salir ERROR) ==='
INSERT INTO incidentes (id, tipo, ubicacion, estado, idempotency_key, inserted_at, updated_at)
SELECT gen_random_uuid(), 'robo', ubicacion, 'sin_verificar', idempotency_key, now(), now()
FROM incidentes
LIMIT 1;

\echo
\echo '=== 10. La base de datos rechaza una descripción de más de 500 caracteres (debe salir ERROR) ==='
INSERT INTO incidentes (id, tipo, descripcion, ubicacion, estado, idempotency_key, inserted_at, updated_at)
VALUES (gen_random_uuid(), 'robo', repeat('a', 501), ST_MakePoint(-71.5340, -16.3963)::geography,
        'sin_verificar', gen_random_uuid(), now(), now());
