import { and, asc, desc, eq, like, ne, or } from "drizzle-orm";
import { Hono } from "hono";
import type { AppBindings } from "../env";
import { requireAuth } from "../auth/session";
import { ascents, badges, userBadges, users } from "../db/schema";
import { normalizeUsername, usernameProblem } from "../lib/validation";
import { ascentsWithPeaks } from "../services/activities";
import { getRelationship } from "../services/relationships";
import { blockedIds, friendStatus, publicUserColumns } from "../services/social";
import { toPublicUser } from "../services/users";
import { canView } from "../services/visibility";

export const usersRoutes = new Hono<AppBindings>();
usersRoutes.use("*", requireAuth);

/** ¿Está libre este usuario? `reason`: invalid, reserved o taken. */
usersRoutes.get("/available", async (c) => {
  const username = normalizeUsername(c.req.query("username") ?? "");
  const problem = usernameProblem(username);
  if (problem) return c.json({ username, available: false, reason: problem });
  const taken = await c.var.db
    .select({ id: users.id })
    .from(users)
    .where(and(eq(users.username, username), ne(users.id, c.var.userId)))
    .get();
  return c.json({ username, available: !taken, reason: taken ? "taken" : null });
});

/** Buscar personas por usuario o nombre (sin bloqueados), con el estado de amistad. */
usersRoutes.get("/search", async (c) => {
  const q = (c.req.query("q") ?? "").trim();
  if (q.length < 2 || q.length > 40) return c.json({ users: [] });
  const db = c.var.db;
  const me = c.var.userId;
  const pattern = `%${q.replace(/[%_\\]/g, "")}%`;
  const rows = await db
    .select(publicUserColumns)
    .from(users)
    .where(and(ne(users.id, me), or(like(users.username, pattern), like(users.displayName, pattern))))
    .orderBy(asc(users.username))
    .limit(25);
  const blocked = await blockedIds(db, me);
  const visible = rows.filter((u) => !blocked.has(u.id));
  const withStatus = await Promise.all(visible.map(async (u) => ({ ...u, friendStatus: await friendStatus(db, me, u.id) })));
  return c.json({ users: withStatus });
});

/**
 * Perfil de una persona: sus cumbres visibles para mí, cifras, emblemas (si somos amigos) y el
 * estado de amistad. Si hay un bloqueo, no existe.
 */
usersRoutes.get("/:username", async (c) => {
  const db = c.var.db;
  const me = c.var.userId;
  const user = await db.select().from(users).where(eq(users.username, normalizeUsername(c.req.param("username")))).get();
  if (!user) return c.json({ error: "not_found" }, 404);
  const rel = await getRelationship(db, me, user.id);
  if (rel === "blocked") return c.json({ error: "not_found" }, 404);

  const list = (await ascentsWithPeaks(db, and(eq(ascents.userId, user.id)))).filter((a) => canView(a.visibility, rel));
  const highest = list.reduce<(typeof list)[number] | null>((best, a) => ((a.peak.ele ?? -Infinity) > (best?.peak.ele ?? -Infinity) ? a : best), null);
  const earned =
    rel === "self" || rel === "friend"
      ? await db
          .select({ id: badges.id, name: badges.name, description: badges.description, tier: badges.tier, category: badges.category, icon: badges.icon, earnedAt: userBadges.earnedAt })
          .from(userBadges)
          .innerJoin(badges, eq(userBadges.badgeId, badges.id))
          .where(eq(userBadges.userId, user.id))
          .orderBy(desc(userBadges.earnedAt))
      : [];
  return c.json({
    ...toPublicUser(user),
    friendStatus: rel === "self" ? "self" : await friendStatus(db, me, user.id),
    summary: { ascents: list.length, uniquePeaks: new Set(list.map((a) => a.peak.id)).size, highestPeak: highest?.peak ?? null },
    ascents: list,
    badges: earned.map((b) => ({ ...b, earnedAt: b.earnedAt.getTime() })),
  });
});
