const BASE32 = "0123456789bcdefghjkmnpqrstuvwxyz";

/** Codifica lat/lon como geohash. */
export function geohashEncode(lat: number, lon: number, precision = 5): string {
  let latMin = -90, latMax = 90, lonMin = -180, lonMax = 180;
  let hash = "";
  let bit = 0;
  let ch = 0;
  let even = true;
  while (hash.length < precision) {
    if (even) {
      const mid = (lonMin + lonMax) / 2;
      if (lon >= mid) { ch = (ch << 1) | 1; lonMin = mid; } else { ch <<= 1; lonMax = mid; }
    } else {
      const mid = (latMin + latMax) / 2;
      if (lat >= mid) { ch = (ch << 1) | 1; latMin = mid; } else { ch <<= 1; latMax = mid; }
    }
    even = !even;
    if (++bit === 5) {
      hash += BASE32[ch];
      bit = 0;
      ch = 0;
    }
  }
  return hash;
}

export function isValidGeohash(s: string): boolean {
  return s.length > 0 && [...s].every((c) => BASE32.includes(c));
}

const EARTH_RADIUS_M = 6_371_008.8;
const toRad = (d: number) => (d * Math.PI) / 180;

/** Distancia ortodrómica en metros. */
export function haversine(aLat: number, aLon: number, bLat: number, bLon: number): number {
  const dLat = toRad(bLat - aLat);
  const dLon = toRad(bLon - aLon);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(toRad(aLat)) * Math.cos(toRad(bLat)) * Math.sin(dLon / 2) ** 2;
  return 2 * EARTH_RADIUS_M * Math.asin(Math.min(1, Math.sqrt(h)));
}

/** Punto de track: [lat, lon, ele?, t?] */
export type TrackPoint = [number, number, number?, number?];

export interface PrivacyZone {
  lat: number;
  lon: number;
  radiusM: number;
}

/**
 * Recorta el inicio y el final del track mientras estén dentro de una zona de privacidad,
 * para que otros usuarios no vean dónde vive o trabaja el autor. Los tramos intermedios
 * que pasen por una zona también se eliminan (el track se parte en segmentos).
 */
export function applyPrivacyZones(track: TrackPoint[], zones: PrivacyZone[]): TrackPoint[][] {
  if (zones.length === 0) return track.length ? [track] : [];
  const inside = (p: TrackPoint) => zones.some((z) => haversine(p[0], p[1], z.lat, z.lon) <= z.radiusM);
  const segments: TrackPoint[][] = [];
  let current: TrackPoint[] = [];
  for (const p of track) {
    if (inside(p)) {
      if (current.length > 1) segments.push(current);
      current = [];
    } else {
      current.push(p);
    }
  }
  if (current.length > 1) segments.push(current);
  return segments;
}
