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

**Fase de diseño.** La arquitectura está propuesta y pendiente de que el equipo confirme algunas decisiones. Todavía no hay código de la app ni del backend.

## Documentación

- [Contexto del MVP](civic-security-contexto-mvp.md): producto, privacidad, reglas de negocio y mockups.
- [Arquitectura del MVP](docs/arquitectura-mvp.md): componentes, modelo de datos, API, seguridad, disponibilidad y plan de entregas.
- [Respuestas del equipo](respuestas_preguntas_armar_arq.txt): insumos usados para definir la arquitectura.
- Mockups en Figma: [Civic Security MVP Mockups](https://www.figma.com/design/DUsoMI54iOjOxD648BoRTG/Civic-Security-MVP-Mockups)

## Estructura del repositorio

```
.
├── app/        # App Flutter (por crear)
├── backend/    # API Elixir + Phoenix (por crear)
├── infra/      # docker-compose, despliegue, respaldos (por crear)
└── docs/       # Arquitectura y decisiones técnicas
```

## Equipo

Proyecto desarrollado por un equipo de 3 estudiantes de la UCSP: desarrollo móvil, backend y diseño.
