import { and, eq } from "drizzle-orm";
import { Hono } from "hono";
import type { AppBindings } from "../env";
import { requireAuth } from "../auth/session";
import { ascents, users } from "../db/schema";
import { newId } from "../lib/ids";
import { isVisibility } from "../lib/validation";
import { ascentsWithPeaks, peaksById, toAscent } from "../services/activities";
import { afterUpload } from "../services/userAchievements";

export const ascentsRoutes = new Hono<AppBindings>();
ascentsRoutes.use("*", requireAuth);

/** Mi biblioteca: todas mis ascensiones con su pico, en orden cronológico. */
ascentsRoutes.get("/", async (c) => {
  const list = await ascentsWithPeaks(c.var.db, and(eq(ascents.userId, c.var.userId)));
  const peakIds = new Set(list.map((a) => a.peak.id));
  const highest = list.reduce<(typeof list)[number] | null>(
    (best, a) => ((a.peak.ele ?? -Infinity) > (best?.peak.ele ?? -Infinity) ? a : best),
    null,
  );
  return c.json({
    ascents: list,
    summary: { ascents: list.length, uniquePeaks: peakIds.size, highestPeak: highest?.peak ?? null },
  });
});

/** Ascensión manual, sin ruta (p. ej. cumbres antiguas de las que no hay GPX). */
ascentsRoutes.post("/", async (c) => {
  const body = await c.req.json<Record<string, unknown>>().catch(() => null);
  if (!body || typeof body !== "object") return c.json({ error: "invalid_body" }, 400);
  const { peakId, summitedAt, note } = body;
  if (!Number.isInteger(peakId)) return c.json({ error: "invalid_peak" }, 400);
  if (typeof summitedAt !== "number" || !Number.isFinite(summitedAt) || summitedAt < 0 || summitedAt > Date.now() + 86_400_000)
    return c.json({ error: "invalid_date" }, 400);
  if (note != null && (typeof note !== "string" || note.length > 500)) return c.json({ error: "invalid_note" }, 400);
  if (body.visibility !== undefined && !isVisibility(body.visibility)) return c.json({ error: "invalid_visibility" }, 400);

  const db = c.var.db;
  const peak = (await peaksById(db, [peakId as number])).get(peakId as number);
  if (!peak) return c.json({ error: "invalid_peak" }, 400);
  const user = await db.select({ defaultVisibility: users.defaultVisibility }).from(users).where(eq(users.id, c.var.userId)).get();
  if (!user) return c.json({ error: "unauthorized" }, 401);

  const [ascent] = await db
    .insert(ascents)
    .values({
      id: newId(),
      userId: c.var.userId,
      peakId: peak.id,
      summitedAt: new Date(summitedAt),
      note: typeof note === "string" ? note.trim() || null : null,
      visibility: (body.visibility as typeof user.defaultVisibility | undefined) ?? user.defaultVisibility,
    })
    .returning();
  const newBadges = await afterUpload(db, c.var.userId);
  return c.json({ ...toAscent(ascent!, peak), newBadges }, 201);
});

ascentsRoutes.patch("/:id", async (c) => {
  const body = await c.req.json<Record<string, unknown>>().catch(() => null);
  if (!body || typeof body !== "object") return c.json({ error: "invalid_body" }, 400);
  const db = c.var.db;
  const where = and(eq(ascents.id, c.req.param("id")), eq(ascents.userId, c.var.userId));
  const ascent = await db.select().from(ascents).where(where).get();
  if (!ascent) return c.json({ error: "not_found" }, 404);

  const update: Partial<typeof ascents.$inferInsert> = {};
  if (body.note !== undefined) {
    if (body.note !== null && (typeof body.note !== "string" || body.note.length > 500))
      return c.json({ error: "invalid_note" }, 400);
    update.note = typeof body.note === "string" ? body.note.trim() || null : null;
  }
  if (body.visibility !== undefined) {
    if (!isVisibility(body.visibility)) return c.json({ error: "invalid_visibility" }, 400);
    update.visibility = body.visibility;
  }
  if (Object.keys(update).length) await db.update(ascents).set(update).where(where);
  const updated = await db.select().from(ascents).where(where).get();
  const peak = (await peaksById(db, [updated!.peakId])).get(updated!.peakId)!;
  return c.json(toAscent(updated!, peak));
});

ascentsRoutes.delete("/:id", async (c) => {
  const where = and(eq(ascents.id, c.req.param("id")), eq(ascents.userId, c.var.userId));
  const ascent = await c.var.db.select({ id: ascents.id }).from(ascents).where(where).get();
  if (!ascent) return c.json({ error: "not_found" }, 404);
  await c.var.db.delete(ascents).where(where);
  return c.body(null, 204);
});
