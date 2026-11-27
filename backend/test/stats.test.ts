import { describe, expect, it } from "vitest";
import { createTestApp } from "./helpers";
import { peaks } from "../src/db/schema";
import { climbRate } from "../src/lib/track";

const ANETO = { id: 1001, name: "Aneto", ele: 3404, lat: 42.6311, lon: 0.6569, geohash: "sp86w" };
const MALADETA = { id: 1002, name: "Maladeta", ele: 3308, lat: 42.6467, lon: 0.6378, geohash: "sp86x" };
// Subida de 1.500 m en 3 h (500 m/h) con puntos cada 5 min y bajada
const track = [
  ...Array.from({ length: 37 }, (_, i) => [42.6476 - i * ((42.6476 - 42.6311) / 36), 0.6626 - i * ((0.6626 - 0.6569) / 36), 1900 + i * (1500 / 36), i * 300]),
  [42.6476, 0.6626, 1900, 36 * 300 + 7200],
];

async function setup() {
  const t = await createTestApp();
  await t.db.insert(peaks).values([ANETO, MALADETA]);
  const ana = await t.signIn("ana", "Ana");
  const bea = await t.signIn("bea", "Bea");
  const json = async (method: string, url: string, token: string, body?: unknown) => {
    const res = await t.request(method, url, { token, body });
    return { status: res.status, body: (await res.json().catch(() => null)) as any };
  };
  const upload = (token: string, startAt: number, extra: Record<string, unknown> = {}) =>
    json("POST", "/v1/activities", token, {
      source: "file", externalId: `x-${Math.random()}`, sportType: "hiking", startAt, durationS: 18000, distanceM: 15000, elevGainM: 1500,
      track: track.map((p) => [p[0], p[1], p[2], p[3]]), ...extra,
    });
  return { ...t, ana, bea, json, upload };
}

describe("climb rate", () => {
  it("measures the vertical speed while climbing and ignores tracks without time", () => {
    expect(climbRate(track as any)).toBe(500);
    expect(climbRate(track.map((p) => [p[0], p[1], p[2]]) as any)).toBeNull();
  });
});

describe("GET /v1/me/stats", () => {
  it("adds up the year, compares with the previous one and finds records", async () => {
    const { json, ana, upload } = await setup();
    await upload(ana.token, Date.UTC(2026, 2, 10, 7));
    await upload(ana.token, Date.UTC(2026, 6, 14, 5), { elevGainM: 2100, ascents: [{ peakId: ANETO.id, summitedAt: Date.UTC(2026, 6, 14, 6, 30) }] });
    await upload(ana.token, Date.UTC(2025, 6, 1, 5), { elevGainM: 900 });
    await upload(ana.token, Date.UTC(2026, 3, 1, 5), { sportType: "cycling", elevGainM: 5000 });

    const { body } = await json("GET", "/v1/me/stats?year=2026", ana.token);
    expect(body.years).toEqual([2026, 2025]);
    expect(body.totals).toMatchObject({ gain: 3600, activities: 2, summits: 1, uniquePeaks: 1 });
    expect(body.previousTotals).toMatchObject({ gain: 900, activities: 1 });
    expect(body.cumulative.current).toEqual([[69, 1500], [195, 3600]]);
    expect(body.monthly[6]).toMatchObject({ month: 7, gain: 2100, activities: 1 });
    expect(body.records.gain.value).toBe(2100);
    expect(body.records.climbRate.value).toBe(500);
    expect(body.records.highestPeak).toMatchObject({ name: "Aneto", ele: 3404 });
    expect(body.peaks).toEqual([expect.objectContaining({ name: "Aneto", count: 1 })]);
    expect(body.calendar.days.map((d: any) => d.date)).toEqual(expect.arrayContaining(["2026-03-10", "2026-07-14"]));

    const all = (await json("GET", "/v1/me/stats?year=all", ana.token)).body;
    expect(all.totals.gain).toBe(4500);
    expect(all.cumulative).toBeNull();
    expect(all.yearly).toEqual([{ year: 2025, gain: 900, activities: 1 }, { year: 2026, gain: 3600, activities: 2 }]);
    expect((await json("GET", "/v1/me/stats?year=1800", ana.token)).status).toBe(400);
  });

  it("returns all my routes, light", async () => {
    const { json, ana, upload } = await setup();
    await upload(ana.token, Date.UTC(2026, 2, 10, 7));
    const { body } = await json("GET", "/v1/me/routes", ana.token);
    expect(body.routes).toHaveLength(1);
    expect(body.routes[0].points.length).toBeLessThanOrEqual(81);
  });
});

describe("GET /v1/friends/leaderboard", () => {
  it("ranks me and my friends this month, without private outings", async () => {
    const { json, ana, bea, upload } = await setup();
    await json("POST", `/v1/friends/${bea.user.id}`, ana.token);
    await json("POST", `/v1/friends/${ana.user.id}/accept`, bea.token);
    const now = Date.now();
    await upload(ana.token, now - 3_600_000, { elevGainM: 800 });
    await upload(bea.token, now - 3_600_000, { elevGainM: 1200 });
    await upload(bea.token, now - 7_200_000, { elevGainM: 5000, visibility: "private" });
    const { body } = await json("GET", "/v1/friends/leaderboard?metric=gain", ana.token);
    expect(body.rows.map((r: any) => [r.user.username, r.value, r.isMe])).toEqual([
      [bea.user.username, 1200, false],
      [ana.user.username, 800, true],
    ]);
    expect((await json("GET", "/v1/friends/leaderboard?metric=nope", ana.token)).status).toBe(400);
  });
});
