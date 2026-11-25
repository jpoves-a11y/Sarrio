import { describe, expect, it } from "vitest";
import { applyPrivacyZones, geohashEncode, haversine, type TrackPoint } from "../src/lib/geo";

describe("geohashEncode", () => {
  it("matches the reference value", () => {
    // Valor de referencia clásico (Wikipedia): 57.64911, 10.40744 → u4pruydqqvj
    expect(geohashEncode(57.64911, 10.40744, 11)).toBe("u4pruydqqvj");
  });
  it("produces nested prefixes (Aneto, 3404 m)", () => {
    const h7 = geohashEncode(42.6311, 0.6569, 7);
    expect(h7).toHaveLength(7);
    expect(geohashEncode(42.6311, 0.6569, 4)).toBe(h7.slice(0, 4));
  });
});

describe("haversine", () => {
  it("measures about 111 km per degree of latitude", () => {
    expect(haversine(0, 0, 1, 0)).toBeCloseTo(111_195, -2);
  });
  it("is zero for the same point", () => {
    expect(haversine(42.6, 0.65, 42.6, 0.65)).toBe(0);
  });
});

describe("applyPrivacyZones", () => {
  const home = { lat: 42.0, lon: 0.0, radiusM: 500 };
  // ~111 m por cada 0.001º de latitud
  const track: TrackPoint[] = Array.from({ length: 20 }, (_, i) => [42.0 + i * 0.001, 0.0]);

  it("returns the track untouched without zones", () => {
    expect(applyPrivacyZones(track, [])).toEqual([track]);
  });

  it("trims the points inside the zone", () => {
    const [segment, ...rest] = applyPrivacyZones(track, [home]);
    expect(rest).toHaveLength(0);
    expect(segment!.every((p) => haversine(p[0], p[1], home.lat, home.lon) > home.radiusM)).toBe(true);
    expect(segment!.length).toBe(15);
  });

  it("splits the track when it crosses a zone midway", () => {
    const mid = { lat: 42.01, lon: 0.0, radiusM: 200 };
    expect(applyPrivacyZones(track, [mid])).toHaveLength(2);
  });
});
