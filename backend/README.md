# Civic Security: backend

API en **Elixir + Phoenix** (REST `/v1` y canal en tiempo real) sobre **PostgreSQL + PostGIS**.

Para levantar la base de datos, el servidor y la app juntos, sigue la
**[guía para ejecutar en local](../docs/guia-ejecucion-local.md)**.

## Comandos más usados

```bash
mix setup          # solo la primera vez: dependencias, base de datos y datos de prueba
mix phx.server     # levanta el servidor en http://127.0.0.1:4000
mix test           # pruebas (crean y usan su propia base civic_test)
mix precommit      # compila sin avisos, formatea y prueba; antes de cada commit
```

La base de datos se levanta con `docker compose -f ../infra/docker-compose.yml up -d`.

Más sobre el diseño: [arquitectura](../docs/arquitectura-mvp.md) y
[revisión de seguridad](../docs/seguridad-revision-1.md).
