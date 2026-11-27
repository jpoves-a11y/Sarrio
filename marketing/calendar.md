# Calendario: arranque en redes

Solo contenido con la app ya publicada en la App Store. No hay piezas de «muy pronto» ni de anuncio del lanzamiento.

El primer bloque está en `marketing/launch`. Se activa eligiendo el día en que empezamos a publicar:

```bash
node tools/social/launch.mjs schedule 2027-03-02
```

Así se crea `marketing/queue/<fecha>-arranque` con las fechas reales y las diapositivas. Revisa el PR y haz merge.

## Mensaje

1. **Tu biblioteca de picos** con cada ascensión en un **mapa 3D**: girarlo, el replay.
2. **Retos y emblemas.**
3. **Con los tuyos:** amigos, feed, me gusta y comentarios.
4. **Estadísticas:** tu año y la cordillera 3D.

De dónde salen las rutas (Apple Health, archivos, Polar) o las cimas añadidas a mano se explicará más adelante.

## Plan (día 0 = primer día de publicaciones, hora de Madrid)

| Día | Red | Pieza | Necesita |
|---|---|---|---|
| 0 | Instagram Reel | Biblioteca y globo | `clip-biblioteca.mp4` |
| 2 | Instagram Reel + TikTok | Replay 3D de una ascensión | `clip-replay.mp4` |
| 4 | Instagram | Carrusel de emblemas | Listo |
| 6 | Instagram Reel + TikTok | Crea tu propio reto | `clip-retos.mp4` |
| 9 | Instagram | Carrusel de retos oficiales | Listo |
| 10 | Bluesky | Gran Slam Ibérico | Listo |
| 12 | Instagram Reel | Amigos y feed | `clip-amigos.mp4` |
| 15 | Instagram Reel | Tu año en cimas | `clip-estadisticas.mp4` |
| 16 | Bluesky | «¿Cuántas cimas has subido este año?» | Listo |

TikTok se publica a mano hasta que aprueben la API. Los textos están pendientes de aprobar.

## Después

Ritmo semanal: 2 Reels, 1 carrusel y 2–3 posts de Bluesky.
- Cima de la semana (Aneto, Mulhacén, Torre Cerredo…): carrusel automático.
- Un emblema o un reto oficial por semana.
- Clips de salidas reales en 3D.
- Más adelante, «cómo funciona»: Apple Health, archivos GPX, FIT y TCX, Polar, y las cimas antiguas añadidas a mano.
