import { haversine, type TrackPoint } from "./geo";

/** Límite de puntos por ruta. La app simplifica antes de subir, así que una salida normal ronda 1.000-3.000. */
export const MAX_TRACK_POINTS = 20_000;

/** Una cumbre se acepta si la ruta pasa a esta distancia de la cima (la app usa 40 m; aquí hay margen). */
export const SUMMIT_VERIFY_RADIUS_M = 100;

const round = (v: number, decimals: number) => {
  const f = 10 ** decimals;
  return Math.round(v * f) / f;
};

/**
 * Valida y normaliza la ruta recibida: `[[lat, lon, ele?, t?], …]`.
 * Devuelve `null` si el formato no es válido.
 */
export function parseTrack(raw: unknown): TrackPoint[] | null {
  if (!Array.isArray(raw) || raw.length > MAX_TRACK_POINTS) return null;
  const out: TrackPoint[] = [];
  for (const p of raw) {
    if (!Array.isArray(p) || p.length < 2 || p.length > 4) return null;
    const [lat, lon, ele, t] = p;
    if (typeof lat !== "number" || typeof lon !== "number") return null;
    if (!Number.isFinite(lat) || !Number.isFinite(lon) || Math.abs(lat) > 90 || Math.abs(lon) > 180) return null;
    if (ele != null && (typeof ele !== "number" || !Number.isFinite(ele))) return null;
    if (t != null && (typeof t !== "number" || !Number.isFinite(t) || t < 0)) return null;
    out.push([round(lat, 6), round(lon, 6), ele == null ? undefined : round(ele, 1), t == null ? undefined : Math.round(t)]);
  }
  return out;
}

export function boundingBox(points: TrackPoint[]) {
  if (points.length === 0) return null;
  let minLat = Infinity, minLon = Infinity, maxLat = -Infinity, maxLon = -Infinity;
  for (const [lat, lon] of points) {
    if (lat < minLat) minLat = lat;
    if (lat > maxLat) maxLat = lat;
    if (lon < minLon) minLon = lon;
    if (lon > maxLon) maxLon = lon;
  }
  return { minLat, minLon, maxLat, maxLon };
}

/** ¿Pasa la ruta cerca de la cima? Evita guardar ascensiones que la ruta no respalda. */
export function trackReaches(points: TrackPoint[], lat: number, lon: number, radiusM = SUMMIT_VERIFY_RADIUS_M) {
  return points.some((p) => haversine(p[0], p[1], lat, lon) <= radiusM);
}

const toJsonPoint = (p: TrackPoint) => [p[0], p[1], p[2] ?? null, p[3] ?? null];

async function pipe(data: Uint8Array, stream: CompressionStream | DecompressionStream): Promise<Uint8Array> {
  const out = new Response(new Blob([data]).stream().pipeThrough(stream));
  return new Uint8Array(await out.arrayBuffer());
}

/** Ruta → gzip(JSON). Formato `gz-json-v1`. */
export async function encodeTrack(points: TrackPoint[]): Promise<Uint8Array> {
  const json = JSON.stringify(points.map(toJsonPoint));
  return pipe(new TextEncoder().encode(json), new CompressionStream("gzip"));
}

export async function decodeTrack(data: Uint8Array | ArrayBuffer): Promise<TrackPoint[]> {
  const bytes = data instanceof Uint8Array ? data : new Uint8Array(data);
  const json = new TextDecoder().decode(await pipe(bytes, new DecompressionStream("gzip")));
  return (JSON.parse(json) as (number | null)[][]).map(
    ([lat, lon, ele, t]) => [lat!, lon!, ele ?? undefined, t ?? undefined] as TrackPoint,
  );
}

/** Formato de salida de la API: `null` en lugar de huecos. */
export function serializeSegments(segments: TrackPoint[][]) {
  return segments.map((s) => s.map(toJsonPoint));
}
