import { describe, expect, it } from "vitest";
import { createTestApp } from "./helpers";
import { challengePeaks, challenges, peaks } from "../src/db/schema";

const ANETO = { id: 1001, name: "Aneto", ele: 3404, lat: 42.6311, lon: 0.6569, geohash: "sp86w", range: "Pirineos" };
const MALADETA = { id: 1002, name: "Maladeta", ele: 3308, lat: 42.6467, lon: 0.6378, geohash: "sp86x", range: "Pirineos" };
const track = [
  [42.6476, 0.6626, 1900, 0],
  [42.6312, 0.657, 3398, 10800],
  [42.6476, 0.6626, 1900, 18000],
];
const upload = {
  source: "file",
  externalId: "gpx-aneto",
  sportType: "hiking",
  startAt: Date.UTC(2026, 6, 14, 5),
  durationS: 18000,
  distanceM: 14800,
  elevGainM: 2100,
  track,
  ascents: [{ peakId: ANETO.id, summitedAt: Date.UTC(2026, 6, 14, 9) }],
};

async function setup() {
  const t = await createTestApp();
  await t.db.insert(peaks).values([ANETO, MALADETA]);
  const ana = await t.signIn("ana", "Ana");
  const bea = await t.signIn("bea", "Bea");
  return { ...t, ana, bea };
}

describe("badges", () => {
  it("returns new badges with the upload and lists them afterwards", async () => {
    const { request, ana } = await setup();
    const res = (await (await request("POST", "/v1/activities", { token: ana.token, body: upload })).json()) as any;
    expect(res.newBadges.map((b: any) => b.id)).toEqual(["first-summit", "alt-2000", "alt-3000", "long-day"]);

    const again = (await (await request("POST", "/v1/activities", { token: ana.token, body: upload })).json()) as any;
    expect(again.newBadges).toEqual([]);

    const list = (await (await request("GET", "/v1/badges", { token: ana.token })).json()) as any;
    expect(list.total).toBe(29);
    expect(list.earned).toBe(4);
    const first = list.badges.find((b: any) => b.id === "first-summit");
    expect(first.earnedAt).toBe(Date.UTC(2026, 6, 14, 9));
    expect(first.activityId).toBe(res.activity.id);
    const four = list.badges.find((b: any) => b.id === "alt-4000");
    expect(four).toMatchObject({ earnedAt: null, progress: { value: 3404, target: 4000 }, tier: "special", icon: "badge-alt-4000" });
  });

  it("awards on manual ascents too", async () => {
    const { request, ana } = await setup();
    const res = await request("POST", "/v1/ascents", { token: ana.token, body: { peakId: MALADETA.id, summitedAt: Date.UTC(2020, 7, 1, 10) } });
    expect(res.status).toBe(201);
    const body = (await res.json()) as any;
    expect(body.peak.name).toBe("Maladeta");
    expect(body.newBadges.map((b: any) => b.id)).toContain("first-summit");
  });
});

describe("challenges", () => {
  it("lists the official challenges with progress and lets me join", async () => {
    const { request, ana } = await setup();
    const featured = (await (await request("GET", "/v1/challenges", { token: ana.token })).json()) as any;
    expect(featured.challenges.length).toBe(12);
    expect(featured.challenges.filter((c: any) => c.badgeId).map((c: any) => c.badgeId)).toEqual(["everesting", "hundred-k"]);
    expect(featured.challenges[0]).toMatchObject({ slug: "everest-year", official: true, joined: false, progress: { target: 8849 } });

    const id = featured.challenges[0].id;
    expect((await request("POST", `/v1/challenges/${id}/join`, { token: ana.token })).status).toBe(200);
    const joined = (await (await request("GET", "/v1/challenges?scope=joined", { token: ana.token })).json()) as any;
    expect(joined.challenges.map((c: any) => c.id)).toEqual([id]);
    expect(joined.challenges[0].participants).toBe(1);

    await request("DELETE", `/v1/challenges/${id}/join`, { token: ana.token });
    const after = (await (await request("GET", "/v1/challenges?scope=joined", { token: ana.token })).json()) as any;
    expect(after.challenges).toEqual([]);
  });

  it("tracks a peak list and marks it completed after the upload", async () => {
    const { request, db, ana } = await setup();
    await db.insert(challenges).values({ id: "official-maladeta", slug: "maladeta", title: "Tresmiles de la Maladeta", kind: "peaks" });
    await db.insert(challengePeaks).values([{ challengeId: "official-maladeta", peakId: ANETO.id }]);
    await request("POST", "/v1/challenges/official-maladeta/join", { token: ana.token });
    await request("POST", "/v1/activities", { token: ana.token, body: upload });

    const detail = (await (await request("GET", "/v1/challenges/official-maladeta", { token: ana.token })).json()) as any;
    expect(detail.challenge.progress).toMatchObject({ value: 1, target: 1, done: true });
    expect(detail.challenge.completedAt).not.toBeNull();
    expect(detail.peaks).toEqual([expect.objectContaining({ name: "Aneto", done: true })]);
  });

  it("awards a list legend when its list is completed, without joining", async () => {
    const { request, db, ana } = await setup();
    await db.insert(challenges).values({ id: "official-slam", slug: "slam", title: "Gran Slam", kind: "peaks", badgeId: "iberian-slam" });
    await db.insert(challengePeaks).values([{ challengeId: "official-slam", peakId: ANETO.id }]);
    const before = (await (await request("GET", "/v1/badges", { token: ana.token })).json()) as any;
    expect(before.badges.find((b: any) => b.id === "iberian-slam").progress).toEqual({ value: 0, target: 1 });
    const res = (await (await request("POST", "/v1/activities", { token: ana.token, body: upload })).json()) as any;
    expect(res.newBadges.map((b: any) => b.id)).toContain("iberian-slam");
    expect(res.newBadges.find((b: any) => b.id === "iberian-slam").tier).toBe("legend");
  });

  it("creates own challenges, private ones hidden from others", async () => {
    const { request, ana, bea } = await setup();
    const bad = await request("POST", "/v1/challenges", { token: ana.token, body: { kind: "peaks", title: "Mis dos", peakIds: [ANETO.id, 4242] } });
    expect(bad.status).toBe(400);

    const res = await request("POST", "/v1/challenges", {
      token: ana.token,
      body: { kind: "peaks", title: "Mis dos", peakIds: [ANETO.id, MALADETA.id], visibility: "private" },
    });
    expect(res.status).toBe(201);
    const { challenge } = (await res.json()) as any;
    expect(challenge.peakCount).toBe(2);

    const mine = (await (await request("GET", "/v1/challenges?scope=mine", { token: ana.token })).json()) as any;
    expect(mine.challenges[0]).toMatchObject({ id: challenge.id, joined: true, progress: { value: 0, target: 2 } });

    expect((await request("GET", `/v1/challenges/${challenge.id}`, { token: bea.token })).status).toBe(404);
    expect((await request("POST", `/v1/challenges/${challenge.id}/join`, { token: bea.token })).status).toBe(404);

    const metric = await request("POST", "/v1/challenges", {
      token: ana.token,
      body: { kind: "metric", title: "Mil metros", metric: "elevation_gain", target: 1000, startsAt: Date.UTC(2026, 0, 1), endsAt: Date.UTC(2027, 0, 1) },
    });
    expect(metric.status).toBe(201);
    expect((await request("DELETE", `/v1/challenges/${challenge.id}`, { token: bea.token })).status).toBe(404);
    expect((await request("DELETE", `/v1/challenges/${challenge.id}`, { token: ana.token })).status).toBe(204);
  });
});
