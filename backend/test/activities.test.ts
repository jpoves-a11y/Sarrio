import { describe, expect, it } from "vitest";
import { createTestApp } from "./helpers";
import { friendships, peaks, privacyZones } from "../src/db/schema";
import { decodeTrack, encodeTrack } from "../src/lib/track";

const ANETO = { id: 1001, name: "Aneto", ele: 3404, lat: 42.6311, lon: 0.6569, geohash: "sp86w" };
const MALADETA = { id: 1002, name: "Maladeta", ele: 3308, lat: 42.6467, lon: 0.6378, geohash: "sp86x" };

/** Subida desde La Besurta (42.6476, 0.6626) hasta la cima del Aneto. */
const track = [
  [42.6476, 0.6626, 1900, 0],
  [42.64, 0.66, 2400, 3600],
  [42.635, 0.658, 3000, 7200],
  [42.6312, 0.657, 3398, 10800],
  [42.64, 0.66, 2400, 14400],
  [42.6476, 0.6626, 1900, 18000],
];

const upload = (extra: Record<string, unknown> = {}) => ({
  source: "file",
  externalId: "gpx-abc",
  sportType: "hiking",
  title: "Aneto por La Besurta",
  startAt: Date.UTC(2026, 6, 14, 5),
  durationS: 18000,
  distanceM: 14800,
  elevGainM: 1500,
  track,
  ascents: [
    { peakId: ANETO.id, summitedAt: Date.UTC(2026, 6, 14, 8) },
    { peakId: MALADETA.id, summitedAt: Date.UTC(2026, 6, 14, 9) }, // la ruta no pasa por aquí
    { peakId: 999999, summitedAt: Date.UTC(2026, 6, 14, 9) }, // no existe
  ],
  ...extra,
});

async function setup() {
  const t = await createTestApp();
  await t.db.insert(peaks).values([ANETO, MALADETA]);
  const ana = await t.signIn("ana", "Ana");
  const bea = await t.signIn("bea", "Bea");
  return { ...t, ana, bea };
}

describe("track encoding", () => {
  it("round-trips through gzip", async () => {
    const pts = [[42.1, 0.5, 1000, 0], [42.2, 0.6, undefined, undefined]] as any;
    const data = await encodeTrack(pts);
    expect(await decodeTrack(data)).toEqual(pts);
  });
});

describe("POST /v1/activities", () => {
  it("stores the activity and only the summits the track supports", async () => {
    const { request, ana } = await setup();
    const res = await request("POST", "/v1/activities", { token: ana.token, body: upload() });
    expect(res.status).toBe(201);
    const body = (await res.json()) as any;
    expect(body.created).toBe(true);
    expect(body.activity.visibility).toBe("friends");
    expect(body.activity.bbox.maxLat).toBeCloseTo(42.6476);
    expect(body.ascents.map((a: any) => a.peak.name)).toEqual(["Aneto"]);
    expect(body.rejectedPeakIds.sort()).toEqual([MALADETA.id, 999999]);
  });

  it("is idempotent per source and external id", async () => {
    const { request, ana } = await setup();
    const first = (await (await request("POST", "/v1/activities", { token: ana.token, body: upload() })).json()) as any;
    const again = await request("POST", "/v1/activities", { token: ana.token, body: upload() });
    expect(again.status).toBe(200);
    const body = (await again.json()) as any;
    expect(body.created).toBe(false);
    expect(body.activity.id).toBe(first.activity.id);
    expect(body.ascents).toHaveLength(1);
  });

  it("validates the payload", async () => {
    const { request, ana } = await setup();
    const bad = async (extra: Record<string, unknown>) =>
      (await request("POST", "/v1/activities", { token: ana.token, body: upload(extra) })).status;
    expect(await bad({ source: "strava" })).toBe(400);
    expect(await bad({ sportType: "Hiking!" })).toBe(400);
    expect(await bad({ track: [[200, 0]] })).toBe(400);
    expect(await bad({ ascents: [{ peakId: "x" }] })).toBe(400);
    expect((await request("POST", "/v1/activities", { body: upload() })).status).toBe(401);
  });
});

describe("GET /v1/activities", () => {
  it("lists my activities with their ascents", async () => {
    const { request, ana, bea } = await setup();
    await request("POST", "/v1/activities", { token: ana.token, body: upload() });
    await request("POST", "/v1/activities", {
      token: ana.token,
      body: upload({ externalId: "gpx-2", startAt: Date.UTC(2026, 7, 1), ascents: [] }),
    });
    const list = (await (await request("GET", "/v1/activities", { token: ana.token })).json()) as any;
    expect(list.activities).toHaveLength(2);
    expect(list.activities[0].externalId).toBeUndefined();
    expect(list.activities[1].ascents).toHaveLength(1);
    const other = (await (await request("GET", "/v1/activities", { token: bea.token })).json()) as any;
    expect(other.activities).toHaveLength(0);
  });
});

describe("GET /v1/activities/:id", () => {
  it("returns the full track to the author", async () => {
    const { request, ana } = await setup();
    const { activity } = (await (await request("POST", "/v1/activities", { token: ana.token, body: upload() })).json()) as any;
    const detail = (await (await request("GET", `/v1/activities/${activity.id}`, { token: ana.token })).json()) as any;
    expect(detail.track).toHaveLength(1);
    expect(detail.track[0]).toHaveLength(track.length);
    expect(detail.track[0][3]).toEqual([42.6312, 0.657, 3398, 10800]);
  });

  it("hides friends-only activities from strangers", async () => {
    const { request, ana, bea } = await setup();
    const { activity } = (await (await request("POST", "/v1/activities", { token: ana.token, body: upload() })).json()) as any;
    expect((await request("GET", `/v1/activities/${activity.id}`, { token: bea.token })).status).toBe(404);
  });

  it("trims privacy zones for friends", async () => {
    const { request, db, ana, bea } = await setup();
    await db.insert(friendships).values({ requesterId: ana.user.id, addresseeId: bea.user.id, status: "accepted" });
    await db.insert(privacyZones).values({ id: "z1", userId: ana.user.id, lat: 42.6476, lon: 0.6626, radiusM: 200 });
    const { activity } = (await (await request("POST", "/v1/activities", { token: ana.token, body: upload() })).json()) as any;
    const res = await request("GET", `/v1/activities/${activity.id}`, { token: bea.token });
    expect(res.status).toBe(200);
    const detail = (await res.json()) as any;
    expect(detail.activity.bbox).toBeNull();
    expect(detail.track.flat()).toHaveLength(track.length - 2);
    expect(detail.ascents).toHaveLength(1);
  });
});

describe("PATCH and DELETE /v1/activities/:id", () => {
  it("updates visibility for the activity and its ascents, and deletes everything", async () => {
    const { request, ana, bea } = await setup();
    const { activity } = (await (await request("POST", "/v1/activities", { token: ana.token, body: upload() })).json()) as any;
    expect((await request("PATCH", `/v1/activities/${activity.id}`, { token: bea.token, body: { title: "x" } })).status).toBe(404);
    const patched = (await (
      await request("PATCH", `/v1/activities/${activity.id}`, { token: ana.token, body: { visibility: "public", title: "Aneto" } })
    ).json()) as any;
    expect(patched.activity.visibility).toBe("public");
    expect(patched.activity.title).toBe("Aneto");
    expect(patched.ascents[0].visibility).toBe("public");
    expect((await request("GET", `/v1/activities/${activity.id}`, { token: bea.token })).status).toBe(200);

    expect((await request("DELETE", `/v1/activities/${activity.id}`, { token: ana.token })).status).toBe(204);
    const lib = (await (await request("GET", "/v1/ascents", { token: ana.token })).json()) as any;
    expect(lib.ascents).toHaveLength(0);
  });
});

describe("/v1/ascents", () => {
  it("builds the library with a summary and supports manual ascents", async () => {
    const { request, ana } = await setup();
    await request("POST", "/v1/activities", { token: ana.token, body: upload() });
    const manual = await request("POST", "/v1/ascents", {
      token: ana.token,
      body: { peakId: MALADETA.id, summitedAt: Date.UTC(2019, 7, 2), note: "Con niebla" },
    });
    expect(manual.status).toBe(201);
    expect(((await manual.json()) as any).activityId).toBeNull();

    const lib = (await (await request("GET", "/v1/ascents", { token: ana.token })).json()) as any;
    expect(lib.ascents.map((a: any) => a.peak.name)).toEqual(["Maladeta", "Aneto"]);
    expect(lib.summary).toEqual({ ascents: 2, uniquePeaks: 2, highestPeak: expect.objectContaining({ name: "Aneto" }) });
  });

  it("rejects unknown peaks and lets only the owner edit or delete", async () => {
    const { request, ana, bea } = await setup();
    expect((await request("POST", "/v1/ascents", { token: ana.token, body: { peakId: 5, summitedAt: 1 } })).status).toBe(400);
    const a = (await (
      await request("POST", "/v1/ascents", { token: ana.token, body: { peakId: ANETO.id, summitedAt: Date.UTC(2020, 1, 1) } })
    ).json()) as any;
    expect((await request("PATCH", `/v1/ascents/${a.id}`, { token: bea.token, body: { note: "x" } })).status).toBe(404);
    const patched = (await (await request("PATCH", `/v1/ascents/${a.id}`, { token: ana.token, body: { note: "¡Cima!" } })).json()) as any;
    expect(patched.note).toBe("¡Cima!");
    expect((await request("DELETE", `/v1/ascents/${a.id}`, { token: bea.token })).status).toBe(404);
    expect((await request("DELETE", `/v1/ascents/${a.id}`, { token: ana.token })).status).toBe(204);
  });
});
