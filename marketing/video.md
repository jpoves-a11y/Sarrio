# Cómo se monta un vídeo

Formato: vertical 1080 × 1920, 30 fps, de 12 a 20 s. Sirve igual para Reels, TikTok y Shorts.

## Estructura

| Tiempo | Imagen | Sonido |
|---|---|---|
| **0–1,5 s · Gancho** | Arranca ya en lo mejor del clip (el 3D moviéndose, el emblema saliendo). Primera frase del texto en grande, arriba. Sin logo al principio. | Empieza la narración con la pregunta o la frase gancho. |
| **1,5–12 s · La app** | El clip grabado dentro de un iPhone, sobre fondo Niebla o Roca. Cortes cada 2–3 s y zoom suave a lo importante (la cifra, el emblema, la cima). Subtítulos de la narración, frase a frase. | Narración + música suave por debajo, que baja cuando se habla. |
| **12–15 s · Cierre** | Símbolo de Sarrio, «Cada cumbre cuenta.» y «En la App Store». | Remate de la música. Sin narración, o solo «Sarrio». |

## Reglas

- **Subtítulos siempre:** la mayoría lo ve sin sonido. Geist Bold, blancos con sombra suave, en el tercio superior.
- **Zonas seguras:** nada importante en los 220 px de arriba ni en los 400 px de abajo, donde Instagram y TikTok ponen sus botones.
- **El mapa, dentro del teléfono:** se ve que es la app (como piden las condiciones de Mapbox), y la atribución del mapa queda a la vista; los subtítulos nunca la tapan.
- **Música:** solo libre de derechos. En TikTok, si el sonido se elige a mano al publicar, la narración va en el vídeo y la música se añade allí.
- **Voz:** la narración dice el texto aprobado de la pieza, o una versión aún más corta. Se marca como contenido generado con IA si la red lo pide.
- **Volumen:** la narración, alrededor de −14 LUFS, y la música unos 18 dB por debajo.

## Proceso (automatizable)

1. Tú grabas el clip (`clips/pedidos.md`).
2. La voz se genera a partir del texto de la pieza.
3. `ffmpeg` monta el clip en el marco del iPhone, los subtítulos, la música y el cierre.
4. El vídeo entra en la cola como cualquier otra pieza y se aprueba en el PR.
