import { describe, expect, it } from "vitest";
import { exportPKCS8, generateKeyPair } from "jose";
import { createTestApp } from "./helpers";
import { peaks, privacyZones } from "../src/db/schema";

const ANETO = { id: 1001, name: "Aneto", ele: 3404, lat: 42.6311, lon: 0.6569, geohash: "sp86w", range: "Pirineos" };
const track = [
  [42.6476, 0.6626, 1900, 0],
  [42.64, 0.66, 2400, 3600],
  [42.6312, 0.657, 3398, 10800],
  [42.6476, 0.6626, 1900, 18000],
];
const upload = (extra: Record<string, unknown> = {}) => ({
  source: "file",
  externalId: `gpx-${Math.random()}`,
  sportType: "hiking",
  startAt: Date.now() - 3_600_000,
  elevGainM: 1500,
  track,
  ascents: [{ peakId: ANETO.id, summitedAt: Date.now() - 1_800_000 }],
  ...extra,
});

async function setup(env: Record<string, string> = {}) {
  const calls: { url: string; body: any; headers: Record<string, string> }[] = [];
  const fakeFetch = (async (url: string, init: RequestInit) => {
    calls.push({ url: String(url), body: JSON.parse(String(init.body)), headers: init.headers as Record<string, string> });
    return new Response("", { status: 200 });
  }) as unknown as typeof fetch;
  const t = await createTestApp({ fetch: fakeFetch, env: env as any });
  await t.db.insert(peaks).values([ANETO]);
  const ana = await t.signIn("ana", "Ana");
  const bea = await t.signIn("bea", "Bea");
  const json = async (method: string, url: string, token: string, body?: unknown) => {
    const res = await t.request(method, url, { token, body });
    return { status: res.status, body: (await res.json().catch(() => null)) as any };
  };
  await json("POST", `/v1/friends/${bea.user.id}`, ana.token);
  await json("POST", `/v1/friends/${ana.user.id}/accept`, bea.token);
  return { ...t, ana, bea, json, calls };
}

async function apnsEnv() {
  const { privateKey } = await generateKeyPair("ES256", { extractable: true });
  return { APNS_KEY: await exportPKCS8(privateKey), APNS_KEY_ID: "KEY123", APNS_TEAM_ID: "TEAM123" };
}

describe("badge count", () => {
  it("counts unread notifications and new friend entries until the feed is seen", async () => {
    const { json, ana, bea } = await setup();
    // Bea tiene el aviso de la solicitud ya aceptada; Ana el de aceptación
    await json("POST", "/v1/activities", ana.token, upload());
    const before = (await json("GET", "/v1/me/badge", bea.token)).body;
    expect(before.feed).toBeGreaterThanOrEqual(1);
    expect(before.total).toBe(before.feed + before.notifications);

    const after = (await json("POST", "/v1/feed/seen", bea.token)).body;
    expect(after.feed).toBe(0);
    await json("POST", "/v1/notifications/read", bea.token);
    expect((await json("GET", "/v1/me/badge", bea.token)).body.total).toBe(0);
  });
});

describe("feed route preview", () => {
  it("brings a light route and trims the owner's privacy zones for friends", async () => {
    const { json, db, ana, bea } = await setup();
    await db.insert(privacyZones).values({ id: "z1", userId: ana.user.id, lat: 42.6476, lon: 0.6626, radiusM: 300 });
    await json("POST", "/v1/activities", ana.token, upload());
    const mine = (await json("GET", "/v1/feed", ana.token)).body.items.find((i: any) => i.kind === "activity");
    expect(mine.route[0]).toHaveLength(4);
    const theirs = (await json("GET", "/v1/feed", bea.token)).body.items.find((i: any) => i.kind === "activity");
    const flat = theirs.route.flat();
    expect(flat.some((p: number[]) => p[0] === 42.6476)).toBe(false);
    expect(flat.length).toBe(2);
  });
});

describe("push", () => {
  it("does nothing without APNs keys", async () => {
    const { json, ana, bea, calls } = await setup();
    await json("POST", "/v1/me/devices", bea.token, { token: "ab".repeat(32), environment: "production" });
    await json("POST", "/v1/activities", ana.token, upload());
    expect(calls).toEqual([]);
    expect((await json("POST", "/v1/me/push-test", bea.token)).status).toBe(503);
  });

  it("tells friends about a recent summit, with the badge count", async () => {
    const { json, ana, bea, calls } = await setup(await apnsEnv());
    await json("POST", "/v1/me/devices", bea.token, { token: "ab".repeat(32), environment: "sandbox" });
    expect((await json("POST", "/v1/me/devices", bea.token, { token: "nope" })).status).toBe(400);
    await json("POST", "/v1/activities", ana.token, upload());
    await new Promise((r) => setTimeout(r, 50));
    const summit = calls.find((c) => c.body.aps.alert.title === "Ana ha hecho cima");
    expect(summit).toBeTruthy();
    expect(summit!.url).toBe(`https://api.sandbox.push.apple.com/3/device/${"ab".repeat(32)}`);
    expect(summit!.body.aps.alert.body).toBe("Aneto · 3404 m".replace("3404", (3404).toLocaleString("es-ES")));
    expect(summit!.body.aps.badge).toBeGreaterThanOrEqual(1);
    expect(summit!.headers["apns-topic"]).toBe("com.sarrio.test");
    expect(summit!.headers.authorization).toMatch(/^bearer ey/);
  });

  it("does not push old imports", async () => {
    const { json, ana, bea, calls } = await setup(await apnsEnv());
    await json("POST", "/v1/me/devices", bea.token, { token: "cd".repeat(32) });
    await json("POST", "/v1/activities", ana.token, upload({ startAt: Date.UTC(2024, 6, 1), ascents: [{ peakId: ANETO.id, summitedAt: Date.UTC(2024, 6, 1, 3) }] }));
    await new Promise((r) => setTimeout(r, 50));
    expect(calls.filter((c) => c.body.aps.alert.title === "Ana ha hecho cima")).toEqual([]);
  });

  it("pushes likes to the author and the test endpoint reports APNs answers", async () => {
    const { json, ana, bea, calls } = await setup(await apnsEnv());
    await json("POST", "/v1/me/devices", ana.token, { token: "ef".repeat(32) });
    await json("POST", "/v1/activities", ana.token, upload());
    const item = (await json("GET", "/v1/feed", bea.token)).body.items.find((i: any) => i.kind === "activity");
    await json("POST", `/v1/likes/feed_item/${item.id}`, bea.token);
    await new Promise((r) => setTimeout(r, 50));
    expect(calls.some((c) => c.body.aps.alert.body === "A Bea le ha gustado «Aneto»")).toBe(true);
    const test = await json("POST", "/v1/me/push-test", ana.token);
    expect(test.body.results).toEqual([{ status: 200, reason: "" }]);
  });
});
