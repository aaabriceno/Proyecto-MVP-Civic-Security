# Civic Security — MVP

Red ciudadana para **reportar incidentes de forma anónima** y **alertar en tiempo real** a quienes están cerca. Piloto en Arequipa, Perú (comunidad UCSP).

Proyecto del curso **ET201 – Formación de Empresas de Base Tecnológica I** (UCSP, semestre 2026-2).

## El problema

En los grupos de WhatsApp de seguridad vecinal circula mucha información, pero la gente no confía en ella porque nadie la verifica. Además, muchas personas no reportan por miedo a ser identificadas.

## La propuesta

1. **Reporte anónimo y seguro:** sin nombre, sin teléfono guardado, sin IP asociada al reporte, sin metadatos EXIF y con rostros difuminados en el propio dispositivo.
2. **Validación comunitaria:** 3 confirmaciones de cuentas verificadas a menos de 1 km marcan el reporte como **Verificado**; 3 votos "Es falso" lo marcan como **Descartado**.
3. **Mapa de calor:** densidad de incidentes por zona y franja horaria (última hora, 24 h, 7 días) para anticipar riesgos.
4. **Alertas por zona:** notificaciones push para las zonas que el usuario suscribe (Casa, Trabajo).

## Stack

| Capa | Tecnología |
|---|---|
| App móvil | Flutter (Dart), Android primero · Riverpod · `flutter_map` + OpenStreetMap · ML Kit |
| Backend | Elixir + Phoenix (REST `/v1` + Phoenix Channels) · Oban |
| Datos | PostgreSQL + PostGIS · Cloudflare R2 para fotos |
| Notificaciones | Firebase Cloud Messaging |
| Seguridad | OWASP MASVS v2 · OWASP ASVS L2 · OWASP API Top 10 · NIST SP 800-63B · Ley N.º 29733 |

## Estado

**MVP en construcción.** Lo que ya funciona:

- **Backend:** API de reportes y mapa (`/v1`), canal en tiempo real, cuentas anónimas (alias y contraseña con Argon2id) y sesiones con renovación segura, con 198 pruebas automáticas.
- **App Android:** mapa en vivo con tu ubicación y su círculo de precisión, filtros, reporte anónimo, y las pantallas de bienvenida, inicio de sesión y registro, con 339 pruebas automáticas.
- **CI:** cada cambio pasa pruebas, análisis estático, auditoría de dependencias y búsqueda de secretos antes de entrar a `main`.

Pendiente: verificación por DNI, validación comunitaria, mapa de calor, alertas por zona y fotos con rostros difuminados.

## Cómo ejecutarlo

**[Guía para ejecutar en local](docs/guia-ejecucion-local.md)**: paso a paso para levantar la base de datos, el servidor y la app en una tablet o teléfono Android (por cable USB o por Wi-Fi).

## Documentación

- [Guía para ejecutar en local](docs/guia-ejecucion-local.md): servidor, base de datos y app en la tablet, paso a paso.
- [Rendimiento del mapa](docs/rendimiento-mapa.md): cómo se mide en una tablet real y qué resultados dio.
- [Contexto del MVP](civic-security-contexto-mvp.md): producto, privacidad, reglas de negocio y mockups.
- [Arquitectura del MVP](docs/arquitectura-mvp.md): componentes, modelo de datos, API, seguridad, disponibilidad y plan de entregas.
- [Respuestas del equipo](respuestas_preguntas_armar_arq.txt): insumos usados para definir la arquitectura.
- Mockups en Figma: [Civic Security MVP Mockups](https://www.figma.com/design/DUsoMI54iOjOxD648BoRTG/Civic-Security-MVP-Mockups)

## Estructura del repositorio

```
.
├── app/            # App Flutter (Android)
├── backend/        # API Elixir + Phoenix
├── infra/          # docker-compose de PostgreSQL + PostGIS
├── docs/           # Guía de ejecución, arquitectura, seguridad y rendimiento
└── Avances-MVP/    # Informes de avance
```

## Equipo

Proyecto desarrollado por un equipo de 3 estudiantes de la UCSP: desarrollo móvil, backend y diseño.
