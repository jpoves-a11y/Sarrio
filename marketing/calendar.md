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

Todo en vídeo: cada clip sale como Reel de Instagram (19:30) y en TikTok (21:00, a mano por ahora). Bluesky, posts cortos de texto.

| Día | Pieza | Texto | Clip |
|---|---|---|---|
| 0 | Biblioteca y globo | «¿Recuerdas todos los picos que has subido? Nosotros tampoco, por eso hicimos Sarrio.» | `clip-biblioteca.mp4` |
| 2 | Replay 3D | «Revive tus cimas en Sarrio.» | `clip-replay.mp4` |
| 4 | Rey del Pirineo | «¿Quién será capaz de ser el primer Rey del Pirineo?» | `clip-emblemas.mp4` |
| 6 | Crea tu reto | Pendiente | `clip-retos.mp4` |
| 9 | Retos oficiales | «¿Cuántos picos te faltan? En Sarrio te retamos a subir unos cuantos más, a ver si eres capaz.» | `clip-retos-oficiales.mp4` |
| 10 | Bluesky | «Aneto, Mulhacén, Torre Cerredo, Almanzor, Moncayo y Teide. ¿Cuántos llevas?» | — |
| 12 | Amigos | «Subir montañas está bien, pero subirlas con amigos está mejor. Etiqueta a ese compañero que te ha visto en los peores momentos.» | `clip-amigos.mp4` |
| 15 | Velocidad de subida | «¿Estarás subiendo montañas más rápido que el año pasado? Compruébalo en Sarrio.» | `clip-estadisticas.mp4` |
| 16 | Bluesky | «¿Cuántas cimas has subido este año? Sin mirar.» | — |

## Después

Ritmo semanal: 2–3 vídeos y 2–3 posts de Bluesky.
- Cima de la semana (Aneto, Mulhacén, Torre Cerredo…).
- Un emblema o un reto oficial por semana.
- Clips de salidas reales en 3D.
- Más adelante, «cómo funciona»: Apple Health, archivos GPX, FIT y TCX, Polar, y las cimas antiguas añadidas a mano.
