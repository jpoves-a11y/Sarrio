import { and, desc, eq, or } from "drizzle-orm";
import { Hono } from "hono";
import type { AppBindings } from "../env";
import { requireAuth } from "../auth/session";
import { blocks, friendships, reports, users } from "../db/schema";
import { newId } from "../lib/ids";
import { displayName, friendStatus, isBlockedEitherWay, notify, publicUsers } from "../services/social";

export const friendsRoutes = new Hono<AppBindings>();
friendsRoutes.use("*", requireAuth);

const between = (a: string, b: string) =>
  or(
    and(eq(friendships.requesterId, a), eq(friendships.addresseeId, b)),
    and(eq(friendships.requesterId, b), eq(friendships.addresseeId, a)),
  );

/** Mis amigos, las solicitudes que me han hecho y las que he enviado. */
friendsRoutes.get("/", async (c) => {
  const me = c.var.userId;
  const rows = await c.var.db
    .select()
    .from(friendships)
    .where(or(eq(friendships.requesterId, me), eq(friendships.addresseeId, me)))
    .orderBy(desc(friendships.createdAt));
  const other = (r: (typeof rows)[number]) => (r.requesterId === me ? r.addresseeId : r.requesterId);
  const people = await publicUsers(c.var.db, rows.map(other));
  const pick = (filter: (r: (typeof rows)[number]) => boolean) =>
    rows
      .filter(filter)
      .map((r) => ({ ...people.get(other(r))!, since: (r.respondedAt ?? r.createdAt).getTime() }))
      .filter((u) => u.id);
  return c.json({
    friends: pick((r) => r.status === "accepted"),
    incoming: pick((r) => r.status === "pending" && r.addresseeId === me),
    outgoing: pick((r) => r.status === "pending" && r.requesterId === me),
  });
});

/** Enviar solicitud. Si el otro ya me la había enviado, queda aceptada. */
friendsRoutes.post("/:userId", async (c) => {
  const db = c.var.db;
  const me = c.var.userId;
  const other = c.req.param("userId");
  if (other === me) return c.json({ error: "invalid_user" }, 400);
  const target = await db.select({ id: users.id }).from(users).where(eq(users.id, other)).get();
  if (!target || (await isBlockedEitherWay(db, me, other))) return c.json({ error: "not_found" }, 404);

  const status = await friendStatus(db, me, other);
  if (status === "friends" || status === "outgoing") return c.json({ status });
  if (status === "incoming") {
    await db
      .update(friendships)
      .set({ status: "accepted", respondedAt: new Date() })
      .where(and(eq(friendships.requesterId, other), eq(friendships.addresseeId, me)));
    await notify(db, { userId: other, actorId: me, kind: "friend_accepted", targetType: "user", targetId: me });
    c.var.push.toUser(other, { title: "Sarrio", body: `${await displayName(db, me)} ha aceptado tu solicitud`, data: { open: "friends" } });
    return c.json({ status: "friends" });
  }
  await db.insert(friendships).values({ requesterId: me, addresseeId: other });
  await notify(db, { userId: other, actorId: me, kind: "friend_request", targetType: "user", targetId: me });
  c.var.push.toUser(other, { title: "Solicitud de amistad", body: `${await displayName(db, me)} quiere ser tu amigo en Sarrio`, data: { open: "friends" } });
  return c.json({ status: "outgoing" }, 201);
});

friendsRoutes.post("/:userId/accept", async (c) => {
  const db = c.var.db;
  const me = c.var.userId;
  const other = c.req.param("userId");
  const where = and(eq(friendships.requesterId, other), eq(friendships.addresseeId, me), eq(friendships.status, "pending"));
  const pending = await db.select().from(friendships).where(where).get();
  if (!pending) return c.json({ error: "not_found" }, 404);
  await db.update(friendships).set({ status: "accepted", respondedAt: new Date() }).where(where);
  await notify(db, { userId: other, actorId: me, kind: "friend_accepted", targetType: "user", targetId: me });
  c.var.push.toUser(other, { title: "Sarrio", body: `${await displayName(db, me)} ha aceptado tu solicitud`, data: { open: "friends" } });
  return c.json({ status: "friends" });
});

/** Quitar amigo, cancelar mi solicitud o rechazar la suya. */
friendsRoutes.delete("/:userId", async (c) => {
  await c.var.db.delete(friendships).where(between(c.var.userId, c.req.param("userId")));
  return c.json({ status: "none" });
});

// ---------------------------------------------------------------------------
// Bloqueos y denuncias
// ---------------------------------------------------------------------------

export const blocksRoutes = new Hono<AppBindings>();
blocksRoutes.use("*", requireAuth);

blocksRoutes.get("/", async (c) => {
  const rows = await c.var.db.select().from(blocks).where(eq(blocks.blockerId, c.var.userId));
  const people = await publicUsers(c.var.db, rows.map((r) => r.blockedId));
  return c.json({ blocked: rows.map((r) => people.get(r.blockedId)).filter(Boolean) });
});

/** Bloquear: deja de ver y de ser visto, y se rompe la amistad. */
blocksRoutes.post("/:userId", async (c) => {
  const db = c.var.db;
  const me = c.var.userId;
  const other = c.req.param("userId");
  if (other === me) return c.json({ error: "invalid_user" }, 400);
  const target = await db.select({ id: users.id }).from(users).where(eq(users.id, other)).get();
  if (!target) return c.json({ error: "not_found" }, 404);
  await db.insert(blocks).values({ blockerId: me, blockedId: other }).onConflictDoNothing();
  await db.delete(friendships).where(between(me, other));
  return c.json({ blocked: true });
});

blocksRoutes.delete("/:userId", async (c) => {
  await c.var.db
    .delete(blocks)
    .where(and(eq(blocks.blockerId, c.var.userId), eq(blocks.blockedId, c.req.param("userId"))));
  return c.json({ blocked: false });
});

export const reportsRoutes = new Hono<AppBindings>();
reportsRoutes.use("*", requireAuth);

const reportTargets = ["user", "comment", "feed_item", "ascent", "activity", "challenge", "user_badge"] as const;

reportsRoutes.post("/", async (c) => {
  const body = await c.req.json<Record<string, unknown>>().catch(() => null);
  if (!body) return c.json({ error: "invalid_body" }, 400);
  const { targetType, targetId, reason } = body;
  if (!(reportTargets as readonly unknown[]).includes(targetType)) return c.json({ error: "invalid_target" }, 400);
  if (typeof targetId !== "string" || !targetId || targetId.length > 100) return c.json({ error: "invalid_target" }, 400);
  if (typeof reason !== "string" || reason.trim().length < 2 || reason.length > 500) return c.json({ error: "invalid_reason" }, 400);
  await c.var.db.insert(reports).values({
    id: newId(),
    reporterId: c.var.userId,
    targetType: targetType as (typeof reportTargets)[number],
    targetId,
    reason: reason.trim(),
  });
  return c.json({ reported: true }, 201);
});
