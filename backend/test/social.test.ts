import { describe, expect, it } from "vitest";
import { createTestApp } from "./helpers";
import { peaks } from "../src/db/schema";

const ANETO = { id: 1001, name: "Aneto", ele: 3404, lat: 42.6311, lon: 0.6569, geohash: "sp86w", range: "Pirineos" };
const track = [
  [42.6476, 0.6626, 1900, 0],
  [42.6312, 0.657, 3398, 10800],
  [42.6476, 0.6626, 1900, 18000],
];
const upload = (extra: Record<string, unknown> = {}) => ({
  source: "file",
  externalId: `gpx-${Math.random()}`,
  sportType: "hiking",
  startAt: Date.UTC(2026, 6, 14, 5),
  durationS: 18000,
  distanceM: 14800,
  elevGainM: 1500,
  track,
  ascents: [{ peakId: ANETO.id, summitedAt: Date.UTC(2026, 6, 14, 9) }],
  ...extra,
});

async function setup() {
  const t = await createTestApp();
  await t.db.insert(peaks).values([ANETO]);
  const ana = await t.signIn("ana", "Ana Pérez");
  const bea = await t.signIn("bea", "Bea Ruiz");
  const carla = await t.signIn("carla", "Carla");
  const json = async (method: string, url: string, token: string, body?: unknown) => {
    const res = await t.request(method, url, { token, body });
    return { status: res.status, body: (await res.json().catch(() => null)) as any };
  };
  const befriend = async () => {
    await json("POST", `/v1/friends/${bea.user.id}`, ana.token);
    await json("POST", `/v1/friends/${ana.user.id}/accept`, bea.token);
  };
  return { ...t, ana, bea, carla, json, befriend };
}

describe("friends", () => {
  it("sends, accepts and lists friend requests, with notifications", async () => {
    const { json, ana, bea } = await setup();
    expect((await json("POST", `/v1/friends/${bea.user.id}`, ana.token)).body.status).toBe("outgoing");
    const beaList = (await json("GET", "/v1/friends", bea.token)).body;
    expect(beaList.incoming.map((u: any) => u.username)).toEqual([ana.user.username]);

    const notes = (await json("GET", "/v1/notifications", bea.token)).body;
    expect(notes.unread).toBe(1);
    expect(notes.notifications[0]).toMatchObject({ kind: "friend_request", actor: { id: ana.user.id } });

    expect((await json("POST", `/v1/friends/${ana.user.id}/accept`, bea.token)).body.status).toBe("friends");
    expect((await json("GET", "/v1/friends", ana.token)).body.friends.map((u: any) => u.id)).toEqual([bea.user.id]);
    expect((await json("GET", "/v1/notifications", ana.token)).body.notifications[0].kind).toBe("friend_accepted");

    await json("POST", "/v1/notifications/read", bea.token);
    expect((await json("GET", "/v1/notifications", bea.token)).body.unread).toBe(0);
  });

  it("accepts automatically when both send a request", async () => {
    const { json, ana, bea } = await setup();
    await json("POST", `/v1/friends/${bea.user.id}`, ana.token);
    expect((await json("POST", `/v1/friends/${ana.user.id}`, bea.token)).body.status).toBe("friends");
  });

  it("searches people with their friend status, hiding blocked ones", async () => {
    const { json, ana, bea, carla } = await setup();
    await json("POST", `/v1/friends/${bea.user.id}`, ana.token);
    const found = (await json("GET", "/v1/users/search?q=be", ana.token)).body.users;
    expect(found).toEqual([expect.objectContaining({ id: bea.user.id, friendStatus: "outgoing" })]);
    await json("POST", `/v1/blocks/${ana.user.id}`, carla.token);
    expect((await json("GET", "/v1/users/search?q=carla", ana.token)).body.users).toEqual([]);
    expect((await json("GET", `/v1/users/${carla.user.username}`, ana.token)).status).toBe(404);
  });

  it("blocking removes the friendship", async () => {
    const { json, ana, bea, befriend } = await setup();
    await befriend();
    await json("POST", `/v1/blocks/${bea.user.id}`, ana.token);
    expect((await json("GET", "/v1/friends", ana.token)).body.friends).toEqual([]);
    expect((await json("POST", `/v1/friends/${bea.user.id}`, ana.token)).status).toBe(404);
    expect((await json("GET", "/v1/blocks", ana.token)).body.blocked.map((u: any) => u.id)).toEqual([bea.user.id]);
  });
});

describe("feed", () => {
  it("shows my and my friends' outings, respecting visibility", async () => {
    const { json, ana, bea, carla, befriend } = await setup();
    await befriend();
    await json("POST", "/v1/activities", ana.token, upload());
    await json("POST", "/v1/activities", ana.token, upload({ visibility: "private", startAt: Date.UTC(2026, 6, 20, 5) }));
    await json("POST", "/v1/activities", carla.token, upload());

    const feed = (await json("GET", "/v1/feed", bea.token)).body.items;
    const outings = feed.filter((i: any) => i.kind === "activity");
    expect(outings).toHaveLength(1);
    expect(outings[0]).toMatchObject({ actor: { id: ana.user.id }, ascents: [expect.objectContaining({ peak: expect.objectContaining({ name: "Aneto" }) })] });
    expect(outings[0].activity.bbox).toBeNull();
    // Los emblemas de Ana también llegan
    expect(feed.some((i: any) => i.kind === "badge" && i.badge.id === "first-summit")).toBe(true);
    // Carla no es amiga: nada suyo
    expect(feed.some((i: any) => i.actor.id === carla.user.id)).toBe(false);

    const mine = (await json("GET", "/v1/feed", ana.token)).body.items.filter((i: any) => i.kind === "activity");
    expect(mine).toHaveLength(2);
  });

  it("updates and removes feed items with the activity", async () => {
    const { json, ana, bea, befriend } = await setup();
    await befriend();
    const { body } = await json("POST", "/v1/activities", ana.token, upload());
    await json("PATCH", `/v1/activities/${body.activity.id}`, ana.token, { visibility: "private" });
    expect((await json("GET", "/v1/feed", bea.token)).body.items.filter((i: any) => i.kind === "activity")).toEqual([]);
    await json("DELETE", `/v1/activities/${body.activity.id}`, ana.token);
    expect((await json("GET", "/v1/feed", ana.token)).body.items.filter((i: any) => i.kind === "activity")).toEqual([]);
  });

  it("likes and comments, with notifications to the author", async () => {
    const { json, ana, bea, carla, befriend } = await setup();
    await befriend();
    await json("POST", "/v1/activities", ana.token, upload());
    const item = (await json("GET", "/v1/feed", bea.token)).body.items.find((i: any) => i.kind === "activity");

    expect((await json("POST", `/v1/likes/feed_item/${item.id}`, bea.token)).status).toBe(200);
    await json("POST", `/v1/likes/feed_item/${item.id}`, bea.token);
    const comment = await json("POST", `/v1/comments/feed_item/${item.id}`, bea.token, { body: "¡Qué día!" });
    expect(comment.status).toBe(201);
    expect((await json("POST", `/v1/comments/feed_item/${item.id}`, bea.token, { body: "  " })).status).toBe(400);

    const again = (await json("GET", "/v1/feed", bea.token)).body.items.find((i: any) => i.id === item.id);
    expect(again).toMatchObject({ likeCount: 1, commentCount: 1, likedByMe: true });

    const notes = (await json("GET", "/v1/notifications", ana.token)).body.notifications;
    expect(notes.map((n: any) => n.kind)).toEqual(["comment", "like", "friend_accepted"]);
    expect(notes[0].label).toBe("Aneto");

    // Carla no es amiga: ni ve ni comenta
    expect((await json("GET", `/v1/comments/feed_item/${item.id}`, carla.token)).status).toBe(404);
    expect((await json("POST", `/v1/likes/feed_item/${item.id}`, carla.token)).status).toBe(404);

    // Ana (dueña) puede borrar el comentario de Bea
    expect((await json("DELETE", `/v1/comments/${comment.body.id}`, ana.token)).status).toBe(204);
    expect((await json("GET", `/v1/comments/feed_item/${item.id}`, bea.token)).body.comments).toEqual([]);
  });

  it("shows a friend's profile with their visible summits and badges", async () => {
    const { json, ana, bea, carla, befriend } = await setup();
    await befriend();
    await json("POST", "/v1/activities", ana.token, upload());
    const asFriend = (await json("GET", `/v1/users/${ana.user.username}`, bea.token)).body;
    expect(asFriend).toMatchObject({ friendStatus: "friends", summary: { uniquePeaks: 1 } });
    expect(asFriend.badges.length).toBeGreaterThan(0);
    const asStranger = (await json("GET", `/v1/users/${ana.user.username}`, carla.token)).body;
    expect(asStranger).toMatchObject({ friendStatus: "none", summary: { ascents: 0 }, badges: [] });
  });

  it("files reports", async () => {
    const { json, ana, bea } = await setup();
    expect((await json("POST", "/v1/reports", ana.token, { targetType: "user", targetId: bea.user.id, reason: "Spam" })).status).toBe(201);
    expect((await json("POST", "/v1/reports", ana.token, { targetType: "nope", targetId: "x", reason: "Spam" })).status).toBe(400);
  });
});
