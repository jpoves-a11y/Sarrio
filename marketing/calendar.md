# Calendario: lanzamiento en la App Store

Todo está preparado en `marketing/launch` y se activa cuando haya fecha:

```bash
node tools/social/launch.mjs schedule 2027-03-02
```

Así se crea `marketing/queue/<fecha>-lanzamiento` con las fechas reales y las diapositivas. Revisa el PR y haz merge.

## Mensaje

Primero, lo que hace la app y por qué engancha:
1. **Tu biblioteca de picos** con cada ascensión en un **mapa 3D**: girarlo, el replay.
2. **Retos y emblemas.**
3. **Con los tuyos:** amigos, feed, me gusta y comentarios.
4. **Estadísticas:** tu año y la cordillera 3D.

De dónde salen las rutas (Apple Health, archivos, Polar) o las cimas añadidas a mano se explicará más adelante, en piezas de «cómo funciona». No son protagonistas del lanzamiento.

## Plan (D = día de lanzamiento, hora de Madrid)

| Día | Red | Pieza | Necesita |
|---|---|---|---|
| D-7 | Instagram + Bluesky | Carrusel «Muy pronto: tu biblioteca de picos» | Listo |
| D-3 | Instagram Reel | Biblioteca y globo | `clip-biblioteca.mp4` |
| D-1 | Bluesky | «Mañana sale Sarrio» | Listo |
| **D** 09:00 | Instagram + Bluesky | Carrusel de lanzamiento: biblioteca, 3D, tu año, retos y emblemas, amigos | Listo |
| **D** 19:30 | Instagram Reel + TikTok | Replay 3D de una ascensión | `clip-replay.mp4` |
| D+2 | Instagram | Carrusel de emblemas | Listo |
| D+4 | Instagram Reel + TikTok | Crea tu propio reto | `clip-retos.mp4` |
| D+7 | Instagram | Carrusel de retos oficiales | Listo |
| D+8 | Bluesky | Gran Slam Ibérico | Listo |
| D+10 | Instagram Reel | Amigos y feed | `clip-amigos.mp4` |
| D+13 | Instagram Reel | Tu año en cimas | `clip-estadisticas.mp4` |
| D+14 | Bluesky | «¿Cuántas cimas has subido este año?» | Listo |

TikTok se publica a mano (hasta que aprueben la API).

## Después del lanzamiento

Ritmo semanal: 2 Reels, 1 carrusel y 2–3 posts de Bluesky. Ideas, en este orden:
- Cima de la semana (Aneto, Mulhacén, Torre Cerredo…): carrusel automático.
- Un emblema o un reto oficial por semana.
- Clips de tus salidas reales en 3D.
- Más adelante, «cómo funciona»: Apple Health, archivos GPX, FIT y TCX, Polar, y las cimas antiguas añadidas a mano.
