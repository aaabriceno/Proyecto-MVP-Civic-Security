# Despliegue en la nube: lista de verificación

Para quien despliegue el servidor (por ejemplo en Fly.io, Render o un VPS). Todo lo de
`docs/guia-ejecucion-local.md` sigue valiendo para probar en la laptop; esto es lo que
**cambia o se agrega** cuando el servidor deja de ser local.

> Estado: esto es una **lista de verificación**, no un despliegue hecho. La parte de TLS
> está comprobada con la configuración real de producción (sección 2); el resto hay que
> verificarlo en el servidor de verdad.

## 1. Variables de entorno

El servidor **no arranca** si falta una variable obligatoria. Ninguna va en el repositorio.

| Variable | Obligatoria | Para qué |
|---|---|---|
| `DATABASE_URL` | sí | `ecto://USUARIO:CLAVE@HOST/BASE`. Con el rol limitado de la sección 3, no con `postgres` |
| `SECRET_KEY_BASE` | sí | Firma los tokens de sesión. `mix phx.gen.secret` |
| `PHX_HOST` | sí | El dominio público (p. ej. `api.civic.pe`) |
| `PHX_SERVER` | sí | `true`: sin esto el servidor no abre el puerto |
| `PORT` | no | Por defecto 4000 |
| `CIVIC_KEY_VERIF_V1` | sí | Clave del HMAC de los DNI |
| `CIVIC_KEY_REP_V1` | sí | Clave del código de autor de cada reporte |
| `CIVIC_KEY_VOTE_V1` | sí | Clave del código de cada voto |
| `CIVIC_UPLOADS_DIR` | sí (mientras las fotos vivan en disco) | Carpeta de las fotos: `0700`, del usuario que corre el programa |
| `CLIENT_IP_HEADER` | si hay proxy | Cabecera con la IP real del cliente (p. ej. `fly-client-ip`). **Solo** si el proxy la **sobrescribe**; si no, todos comparten la IP del proxy y los límites se rompen |
| `CIVIC_CUPO_SIN_VERIFICAR`, `CIVIC_CUPO_VERIFICADO` | no | Cupo diario de reportes (por defecto 3 y 10) |

Las tres claves `CIVIC_KEY_*` deben ser **distintas entre sí** y de 32 bytes en base64:
`openssl rand -base64 32` (una vez por cada una). Si se pierde `CIVIC_KEY_VERIF_V1`, los DNI
ya verificados dejan de reconocerse; si se filtra junto con la base de datos, se pueden
adivinar DNI (solo hay 10⁸ posibles). Guárdalas en el gestor de secretos del proveedor y
respáldalas **aparte** de la base de datos.

## 2. TLS (https)

**Qué ya hace el código** (no hay que programar nada):

- En producción el servidor responde `301`/`307` a `https` ante cualquier petición por
  `http`, y manda `Strict-Transport-Security: max-age=31536000` (HSTS, un año) en las
  respuestas por `https`.
- La app de producción **se niega** a usar `http` (`validateApiUrl`) y el manifiesto de la
  versión *release* tiene `usesCleartextTraffic="false"`.
- Excepción deliberada: `localhost` y `127.0.0.1` (para probar en la laptop).

**Lo que falta, y hay que hacer al desplegar:**

1. **Un certificado.** Lo normal es que el proveedor (Fly.io, Render, Cloudflare...) termine
   el TLS por ti y entregue un certificado gratis y renovable; tú solo apuntas el dominio.
2. **El proxy debe mandar `x-forwarded-proto`.** El servidor decide si la petición llegó por
   `https` leyendo esa cabecera (`rewrite_on: [:x_forwarded_proto]`). Si el proxy no la pone,
   todo se redirige en bucle; si un cliente pudiera falsificarla, se saltaría la
   redirección. El proxy debe **sobrescribirla**, no pasarla tal cual.
3. Que el puerto del servidor **no** sea alcanzable directamente desde internet: solo el
   proxy, que habla con él por la red privada.

**Cómo comprobarlo** una vez desplegado:

```bash
curl -sI http://api.tu-dominio.pe/health | head -3      # esperado: 301 con location: https://...
curl -sI https://api.tu-dominio.pe/health | grep -i strict-transport   # esperado: max-age=31536000
```

**Comprobado el 2026-11-15** con la configuración de producción real (arrancada localmente,
sin abrir ningún puerto): `http` plano → `301` a `https`; subir una foto por `http` plano →
`307` a `https` (conserva el método); detrás de un proxy que dice `x-forwarded-proto: https`
→ `200` con HSTS de un año; `127.0.0.1` → `200` sin redirección.

**Una advertencia sobre las fotos:** una redirección ocurre *después* de que el servidor
recibió la petición. Una foto enviada por `http` plano ya habría viajado en claro. Lo que lo
impide es la **app** (la versión de producción no habla `http`), no la redirección.

**HSTS:** cuando el dominio ya tenga su certificado y todo funcione, no quites HSTS: los
navegadores recuerdan la regla un año.

## 3. Privilegios mínimos

La idea no es que "solo root entre", sino lo contrario: que **casi nada corra como root** y
que cada pieza pueda hacer solo lo que necesita. Si algo cae, el daño queda acotado.

- [ ] El programa corre con un **usuario del sistema sin privilegios** (no root, sin shell
      interactiva).
- [ ] **Rol de base de datos limitado** para la app: puede leer y escribir las tablas, y
      nada más (ni crear roles, ni borrar la base, ni `COPY` a archivos). Hoy, en desarrollo,
      se usa el superusuario `postgres`: **en producción no**. Las migraciones se corren con
      otro rol, con más permisos, y no desde el programa.
- [ ] La base de datos **no es alcanzable desde internet**: solo desde el servidor de la app.
- [ ] Acceso al servidor **solo con llaves SSH**, sin contraseña y sin entrar como root
      directamente (`PermitRootLogin no`, `PasswordAuthentication no`).
- [ ] Firewall: abierto el 443 (y el 22 desde tu IP, si hace falta); todo lo demás, cerrado.
- [ ] **Doble factor** en la cuenta del proveedor de nube, en GitHub y en el correo con el que
      se crearon. Es lo que más protege contra el robo de credenciales.
- [ ] Contraseñas largas (12 caracteres o más) y distintas, en un gestor de contraseñas.
- [ ] Los secretos viven en el gestor del proveedor, **no** en el repositorio ni en el chat.
      El CI ya revisa que no se suban (gitleaks).
- [ ] La carpeta de fotos es `0700` y de ese mismo usuario; si se usa un bucket, es
      **privado** y sin listado público.
- [ ] Pocas personas con acceso, y cada una con su propia cuenta (nunca una compartida).

Esto **no** impide que alguien con acceso al servidor vea las fotos: el servidor las lee
para mostrarlas. Reduce quién puede llegar ahí y qué más puede tocar.

## 4. Fotos

- Hoy se guardan en disco (`CIVIC_UPLOADS_DIR`). Para pasar a un bucket (Cloudflare R2, S3)
  se escribe otro módulo que cumpla `Civic.Evidence.Store` (`put/2`, `get/1`, `delete/1`) y
  se cambia `config :civic, Civic.Evidence, store: ...`. Nada más cambia.
- **Cifrado en reposo:** no se construye cifrado propio. Se usa el del proveedor: R2 y S3
  cifran todo por defecto; en un VPS, el cifrado de disco del proveedor. Protege contra "se
  llevan el disco o el respaldo", no contra alguien que ya está dentro del servidor.
- **Respaldos:** si las fotos están en disco, hay que respaldarlas (y respaldar la base con
  el mismo cuidado). Un respaldo sin cifrar anula todo lo anterior.
- **Retención (pendiente de implementar):** fotos de reportes descartados, 30 días; las
  demás, 1 año. Hoy no se borran solas.
- Límites honestos que se dicen en la defensa: el servidor **puede ver** las fotos (se
  muestran en el mapa público); **no se difuminan rostros ni placas**; los metadatos sí se
  quitan (la app los elimina y el servidor lo comprueba).

## 5. Antes de abrir al público

- [ ] `mix test`, `mix format --check-formatted`, `mix sobelow`, `mix deps.audit` en verde en
      el CI de `main`.
- [ ] Las tres claves `CIVIC_KEY_*` generadas, **distintas** y respaldadas.
- [ ] `curl` de la sección 2 con el resultado esperado.
- [ ] La app *release* se compila con `API_URL=https://...` (con `http` ni arranca).
- [ ] Probado de punta a punta con el APK *release* instalado en un teléfono real **con
      datos móviles**, no por el cable ni por el Wi-Fi de la casa.
- [ ] Rol de base de datos limitado creado y en uso (sección 3).
- [ ] Respaldo de la base hecho **y restaurado una vez** en otro lugar (un respaldo que
      nunca se probó no es un respaldo).
