import { asc, eq } from "drizzle-orm";
import { Hono } from "hono";
import type { AppBindings } from "../env";
import { requireAuth } from "../auth/session";
import { badges, userBadges } from "../db/schema";
import { awardBadges } from "../services/userAchievements";

export const badgesRoutes = new Hono<AppBindings>();
badgesRoutes.use("*", requireAuth);

/**
 * Catálogo de emblemas con los míos: fecha y actividad con que se ganaron, y el progreso de los
 * que faltan. Evalúa antes las reglas, así que los emblemas de actividades antiguas aparecen solos.
 */
badgesRoutes.get("/", async (c) => {
  const db = c.var.db;
  const userId = c.var.userId;
  const { evaluation } = await awardBadges(db, userId);
  const [catalog, mine] = await Promise.all([
    db.select().from(badges).orderBy(asc(badges.sortOrder)),
    db.select().from(userBadges).where(eq(userBadges.userId, userId)),
  ]);
  const byId = new Map(mine.map((m) => [m.badgeId, m]));
  const list = catalog.map((b) => {
    const m = byId.get(b.id);
    const p = evaluation.progress.get(b.id);
    return {
      id: b.id,
      name: b.name,
      description: b.description,
      tier: b.tier,
      category: b.category,
      icon: b.icon,
      earnedAt: m ? m.earnedAt.getTime() : null,
      activityId: m?.activityId ?? null,
      ascentId: m?.ascentId ?? null,
      progress: m || !p ? null : { value: Math.min(p.value, p.target), target: p.target },
    };
  });
  return c.json({ badges: list, earned: mine.length, total: catalog.length });
});
