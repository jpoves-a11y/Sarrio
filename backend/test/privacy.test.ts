import { describe, expect, it } from "vitest";
import { createTestApp } from "./helpers";
import { peaks } from "../src/db/schema";

const ANETO = { id: 1001, name: "Aneto", ele: 3404, lat: 42.6311, lon: 0.6569, geohash: "sp86w" };
const track = [
  [42.6476, 0.6626, 1900, 0],
  [42.64, 0.66, 2400, 3600],
  [42.6312, 0.657, 3398, 10800],
];

describe("privacy zones", () => {
  it("creates, lists and deletes my zones, and trims my routes for friends", async () => {
    const t = await createTestApp();
    await t.db.insert(peaks).values([ANETO]);
    const ana = await t.signIn("ana", "Ana");
    const bea = await t.signIn("bea", "Bea");
    const json = async (method: string, url: string, token: string, body?: unknown) => {
      const res = await t.request(method, url, { token, body });
      return { status: res.status, body: (await res.json().catch(() => null)) as any };
    };
    expect((await json("POST", "/v1/me/privacy-zones", ana.token, { lat: 42.6476, lon: 0.6626, radiusM: 50 })).status).toBe(400);
    expect((await json("POST", "/v1/me/privacy-zones", ana.token, { lat: 120, lon: 0, radiusM: 500 })).status).toBe(400);
    const zone = await json("POST", "/v1/me/privacy-zones", ana.token, { lat: 42.6476, lon: 0.6626, radiusM: 300 });
    expect(zone.status).toBe(201);
    expect((await json("GET", "/v1/me/privacy-zones", ana.token)).body.zones).toEqual([zone.body]);
    expect((await json("GET", "/v1/me/privacy-zones", bea.token)).body.zones).toEqual([]);

    await json("POST", `/v1/friends/${bea.user.id}`, ana.token);
    await json("POST", `/v1/friends/${ana.user.id}/accept`, bea.token);
    const up = await json("POST", "/v1/activities", ana.token, {
      source: "file", externalId: "z", sportType: "hiking", startAt: Date.UTC(2026, 6, 1), track,
      ascents: [{ peakId: ANETO.id, summitedAt: Date.UTC(2026, 6, 1, 3) }],
    });
    const asFriend = await json("GET", `/v1/activities/${up.body.activity.id}`, bea.token);
    expect(asFriend.body.track.flat().length).toBe(2);
    const asMe = await json("GET", `/v1/activities/${up.body.activity.id}`, ana.token);
    expect(asMe.body.track.flat().length).toBe(3);

    // Otra persona no puede borrar mi zona
    await json("DELETE", `/v1/me/privacy-zones/${zone.body.id}`, bea.token);
    expect((await json("GET", "/v1/me/privacy-zones", ana.token)).body.zones).toHaveLength(1);
    expect((await json("DELETE", `/v1/me/privacy-zones/${zone.body.id}`, ana.token)).status).toBe(204);
    expect((await json("GET", "/v1/me/privacy-zones", ana.token)).body.zones).toEqual([]);
  });
});
