---
name: sarrio-social
description: Voz de marca y reglas para escribir cualquier pieza de marketing de Sarrio (posts de Instagram, TikTok, YouTube Shorts, Bluesky, Threads, ficha de App Store, web, notas de prensa, mensajes a clubes). Úsala siempre antes de redactar o revisar textos promocionales de la app.
---

# Marketing de Sarrio

La guía de marca completa está en `brand/README.md`. Léela entera antes de escribir: personalidad, voz, slogans, lo visual y la lista de funciones.

## Regla 1: solo lo que la app hace hoy

Solo se menciona lo que la app ofrece de verdad. Antes de entregar cualquier pieza:

1. Haz la lista de cada función que la pieza menciona o deja entrever (también en imágenes, vídeos y hashtags).
2. Compara cada una con «Lo que ofrece hoy» en `brand/README.md`.
3. Si alguna no está en esa lista, compruébala en el código (`ios/Sarrio/Features`, `backend/src/routes`, `README.md` → «Fuentes de datos»).
   - Si existe, úsala y añádela a la lista de `brand/README.md` en el mismo cambio.
   - Si no existe o no estás seguro, quítala de la pieza.
4. Nunca: fotos en actividades, Garmin, Suunto, COROS, Strava, Android, rankings, ni funciones del plan que no estén publicadas.

Al final de cada borrador, añade una línea `Funciones mencionadas:` con la lista, para que quien lo apruebe pueda revisarla de un vistazo.

## Regla 2: la voz

- Compañero de cordada: tuteo, cercano, sereno, con humor seco y vocabulario de montaña.
- Frases cortas. Cifras con unidades («3.404 m»). Como mucho un emoji, de paisaje.
- Sin tono de coach, sin «la mejor app», sin exclamaciones en cadena.
- Habla de la persona y de la montaña, no de la tecnología.
- Los slogans, tal cual están en `brand/README.md`. No inventes otros como firma.

## Regla 3: mapas y datos

- Mapbox solo aparece en grabaciones de pantalla hechas por una persona usando la app, con la interfaz visible y la atribución a la vista. Al editar un clip, no la recortes ni la tapes; si el encuadre la deja fuera, añádela en texto en una esquina.
- No generes imágenes ni vídeos con Mapbox de forma automática, ni imágenes estáticas con su satélite.
- Las piezas automáticas usan fuentes abiertas (MapLibre, IGN) con su atribución.
- Datos de picos: «© OpenStreetMap contributors».

## Regla 4: personas y privacidad

- No se muestra la actividad, el nombre ni la ruta de ningún usuario sin su permiso expreso y por escrito.
- Nunca se muestran el inicio ni el final de una ruta.
- Las fotos de personas, solo de la propia cuenta o con permiso de quien sale.

## Formatos

| Red | Texto | Notas |
|---|---|---|
| Instagram Reel | Gancho en la primera línea (≤ 60 caracteres), 2–4 líneas, llamada a la acción suave, 5–8 hashtags al final | Portada con la cifra o la cima en grande |
| Instagram carrusel | Diapositiva 1 = gancho; 4–8 diapositivas; la última, slogan y logo | Plantillas de marca, tipografía Geist |
| TikTok | 1–2 líneas y 3–5 hashtags | El sonido se elige a mano al publicar |
| YouTube Shorts | Título ≤ 60 caracteres y descripción de 2 líneas | |
| Bluesky / Threads | Hasta 280 caracteres, tono de conversación | Una imagen como mucho |
| App Store | Subtítulo: «Tu biblioteca de picos» | Capturas con una frase cada una |

Hashtags base, para elegir según la pieza: `#montaña #cumbres #picos #senderismo #alpinismo #pirineos #tresmiles #montañismo #sarrio`.

## Entrega

Cada borrador es un `.md` en `marketing/queue/<fecha>/` con este frontmatter:

```yaml
red: instagram-reel   # ver la tabla de abajo
fecha: 2026-12-08T19:30:00+01:00   # siempre con zona horaria (+01:00 en invierno, +02:00 en verano)
recursos: [clip-aneto.mp4]
alt: Texto alternativo de la imagen   # opcional; Bluesky
portada: portada-aneto.jpg            # opcional; solo instagram-reel
```

| `red` | Se publica | Recursos |
|---|---|---|
| `bluesky` | Sola | 0–4 imágenes (≤ 1 MB) |
| `instagram-imagen` | Sola | 1 JPEG |
| `instagram-carrusel` | Sola | 2–10 JPEG |
| `instagram-reel` | Sola | 1 vídeo |
| `tiktok`, `youtube-short`, `threads` | A mano | Vídeo (Threads: 0–1 imagen) |

Después va el texto final y, al cierre, la línea `Funciones mencionadas:`. Nada se publica sin que una persona lo apruebe.

Las imágenes de marca salen de `tools/social/render.mjs` (diapositivas desde un `slides.json`). Antes de abrir el PR, ejecuta `node tools/social/publish.mjs validate`.
