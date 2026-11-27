# Marketing en redes

Cómo se preparan, aprueban y publican las piezas de Sarrio. La voz, los slogans y lo que se puede anunciar están en `brand/README.md`. Las reglas para redactar, en `.claude/skills/sarrio-social`.

## Flujo

```
calendar.md ─▶ borradores (Claude) ─▶ PR ─▶ tú revisas y haces merge ─▶ GitHub Action publica en su fecha
                  ▲                                                               │
     clips/inbox (tus grabaciones de la app)                    published/log.json ◀┘
```

1. **Calendario.** `calendar.md` tiene el plan del mes: temas, cimas y los clips que hacen falta.
2. **Clips.** Grabas la pantalla del iPhone usando la app (lista en `clips/pedidos.md`) y los dejas en `clips/inbox/`.
3. **Borradores.** Claude escribe cada pieza en `queue/<lunes de la semana>/` y abre un PR.
4. **Aprobación.** Revisas el PR: textos, imágenes y la línea «Funciones mencionadas». Lo que no te guste, lo cambias o lo borras. **Merge = aprobado.**
5. **Publicación.** La Action «Publicar en redes» mira la cola cada 30 minutos y publica lo que ya está en `main` y ha llegado a su hora. Lo apunta en `published/log.json` para no repetirlo.

Una pieza con más de 3 días de retraso no sale sola: cámbiale la fecha. TikTok, YouTube Shorts y Threads se publican a mano por ahora; la cola los valida igual.

## Formato de una pieza

```markdown
---
red: instagram-carrusel        # bluesky | instagram-imagen | instagram-carrusel | instagram-reel | tiktok | youtube-short | threads
fecha: 2026-12-04T19:30:00+01:00
recursos: [aneto-01.jpg, aneto-02.jpg]
alt: Texto alternativo          # opcional (Bluesky)
---
El texto tal cual se publica.

Funciones mencionadas: biblioteca de cumbres
```

Las diapositivas se generan desde un `slides.json` (ver la cabecera de `tools/social/render.mjs`):

```bash
node tools/social/render.mjs marketing/queue/2026-11-30/aneto
```

Antes de abrir el PR:

```bash
node tools/social/publish.mjs validate
```

Para ver qué se publicaría ahora mismo:

```bash
node tools/social/publish.mjs publish --dry-run
```

## Mapas

Las diapositivas automáticas no llevan mapas de Mapbox. Mapbox solo aparece en tus grabaciones de la app, con la interfaz visible y la atribución a la vista. Detalle en `brand/README.md` → Mapas.

## Configurar las redes

Los secretos van en GitHub: Settings → Secrets and variables → Actions. Mientras falte el de una red, sus piezas esperan sin dar error.

| Red | Secretos | Dónde se consiguen |
|---|---|---|
| Bluesky | `BLUESKY_HANDLE` (p. ej. `sarrio.bsky.social`), `BLUESKY_APP_PASSWORD` | Bluesky → Ajustes → Privacidad y seguridad → Contraseñas de aplicación |
| Instagram | `IG_USER_ID`, `IG_ACCESS_TOKEN` | Cuenta profesional + app en developers.facebook.com con «Instagram API with Instagram Login» y el permiso `instagram_business_content_publish`. El token de larga duración caduca a los 60 días: hay que renovarlo. |

Instagram descarga las imágenes desde `raw.githubusercontent.com` (el repositorio es público), así que solo publica lo que ya está en `main`.
