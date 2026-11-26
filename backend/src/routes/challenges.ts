import { and, asc, count, desc, eq, inArray, isNull } from "drizzle-orm";
import { Hono } from "hono";
import type { AppBindings } from "../env";
import { requireAuth } from "../auth/session";
import { challengeMetricValues, challengeParticipants, challengePeaks, challenges, peaks, users } from "../db/schema";
import { newId } from "../lib/ids";
import { isVisibility } from "../lib/validation";
import { challengeProgress } from "../services/achievements";
import { getRelationship } from "../services/relationships";
import { canView } from "../services/visibility";
import { loadHistory, peakIdsFor, toChallengeDef, type ChallengeRow } from "../services/userAchievements";

export const challengesRoutes = new Hono<AppBindings>();
challengesRoutes.use("*", requireAuth);

const MAX_PEAKS = 100;

async function participantCounts(db: AppBindings["Variables"]["db"], ids: string[]) {
  if (!ids.length) return new Map<string, number>();
  const rows = await db
    .select({ id: challengeParticipants.challengeId, n: count() })
    .from(challengeParticipants)
    .where(inArray(challengeParticipants.challengeId, ids))
    .groupBy(challengeParticipants.challengeId);
  return new Map(rows.map((r) => [r.id, r.n]));
}

function toChallenge(c: ChallengeRow) {
  return {
    id: c.id,
    slug: c.slug,
    official: c.creatorId == null,
    creatorId: c.creatorId,
    title: c.title,
    description: c.description,
    visibility: c.visibility,
    kind: c.kind,
    metric: c.metric,
    target: c.target,
    sport: c.sport,
    minEle: c.minEle,
    recurrence: c.recurrence,
    window: c.window,
    startsAt: c.startsAt?.getTime() ?? null,
    endsAt: c.endsAt?.getTime() ?? null,
  };
}

/**
 * Retos con mi progreso. `scope`:
 *  - `featured` (por defecto): los oficiales;
 *  - `joined`: a los que estoy unido;
 *  - `mine`: los que he creado.
 */
challengesRoutes.get("/", async (c) => {
  const db = c.var.db;
  const userId = c.var.userId;
  const scope = c.req.query("scope") ?? "featured";
  let rows: ChallengeRow[];
  if (scope === "joined") {
    rows = (
      await db
        .select({ c: challenges })
        .from(challengeParticipants)
        .innerJoin(challenges, eq(challengeParticipants.challengeId, challenges.id))
        .where(eq(challengeParticipants.userId, userId))
        .orderBy(desc(challengeParticipants.joinedAt))
    ).map((r) => r.c);
  } else if (scope === "mine") {
    rows = await db.select().from(challenges).where(eq(challenges.creatorId, userId)).orderBy(desc(challenges.createdAt));
  } else if (scope === "featured") {
    rows = await db.select().from(challenges).where(isNull(challenges.creatorId)).orderBy(asc(challenges.sortOrder));
  } else {
    return c.json({ error: "invalid_scope" }, 400);
  }

  const ids = rows.map((r) => r.id);
  const [history, peakMap, counts, joinedRows] = await Promise.all([
    loadHistory(db, userId),
    peakIdsFor(db, ids),
    participantCounts(db, ids),
    ids.length
      ? db
          .select()
          .from(challengeParticipants)
          .where(and(eq(challengeParticipants.userId, userId), inArray(challengeParticipants.challengeId, ids)))
      : Promise.resolve([]),
  ]);
  const joined = new Map(joinedRows.map((j) => [j.challengeId, j]));
  return c.json({
    challenges: rows.map((r) => {
      const peakIds = peakMap.get(r.id) ?? [];
      const { donePeakIds: _omit, ...progress } = challengeProgress(toChallengeDef(r, peakIds), history);
      const j = joined.get(r.id);
      return {
        ...toChallenge(r),
        peakCount: r.kind === "peaks" ? peakIds.length : null,
        participants: counts.get(r.id) ?? 0,
        joined: !!j,
        joinedAt: j?.joinedAt.getTime() ?? null,
        completedAt: j?.completedAt?.getTime() ?? null,
        progress,
      };
    }),
  });
});

async function visibleChallenge(c: { var: AppBindings["Variables"] }, id: string) {
  const row = await c.var.db.select().from(challenges).where(eq(challenges.id, id)).get();
  if (!row) return null;
  if (row.creatorId == null || row.creatorId === c.var.userId) return row;
  const rel = await getRelationship(c.var.db, c.var.userId, row.creatorId);
  return canView(row.visibility, rel) ? row : null;
}

/** Detalle: progreso y, en los de lista, cada cima con su estado. */
challengesRoutes.get("/:id", async (c) => {
  const db = c.var.db;
  const row = await visibleChallenge(c, c.req.param("id"));
  if (!row) return c.json({ error: "not_found" }, 404);
  const [history, peakMap, counts, j, creator] = await Promise.all([
    loadHistory(db, c.var.userId),
    peakIdsFor(db, [row.id]),
    participantCounts(db, [row.id]),
    db
      .select()
      .from(challengeParticipants)
      .where(and(eq(challengeParticipants.userId, c.var.userId), eq(challengeParticipants.challengeId, row.id)))
      .get(),
    row.creatorId
      ? db.select({ id: users.id, username: users.username, displayName: users.displayName }).from(users).where(eq(users.id, row.creatorId)).get()
      : Promise.resolve(null),
  ]);
  const peakIds = peakMap.get(row.id) ?? [];
  const { donePeakIds, ...progress } = challengeProgress(toChallengeDef(row, peakIds), history);
  const done = new Set(donePeakIds ?? []);
  const peakRows = peakIds.length
    ? await db
        .select({ id: peaks.id, name: peaks.name, nameEs: peaks.nameEs, ele: peaks.ele, lat: peaks.lat, lon: peaks.lon, range: peaks.range })
        .from(peaks)
        .where(inArray(peaks.id, peakIds))
        .orderBy(desc(peaks.ele))
    : [];
  return c.json({
    challenge: {
      ...toChallenge(row),
      peakCount: row.kind === "peaks" ? peakIds.length : null,
      participants: counts.get(row.id) ?? 0,
      joined: !!j,
      joinedAt: j?.joinedAt.getTime() ?? null,
      completedAt: j?.completedAt?.getTime() ?? null,
      progress,
      creator: creator ?? null,
    },
    peaks: peakRows.map((p) => ({ ...p, done: done.has(p.id) })),
  });
});

/**
 * Crear un reto propio:
 *  - de meta: `{ kind: "metric", metric, target, startsAt?, endsAt? }`;
 *  - de lista: `{ kind: "peaks", peakIds: [...] }`.
 * Quien lo crea queda unido.
 */
challengesRoutes.post("/", async (c) => {
  const body = await c.req.json<Record<string, unknown>>().catch(() => null);
  if (!body || typeof body !== "object") return c.json({ error: "invalid_body" }, 400);
  const title = typeof body.title === "string" ? body.title.trim() : "";
  if (title.length < 2 || title.length > 80) return c.json({ error: "invalid_title" }, 400);
  const description = body.description == null ? null : typeof body.description === "string" ? body.description.trim().slice(0, 300) || null : undefined;
  if (description === undefined) return c.json({ error: "invalid_description" }, 400);
  if (body.visibility !== undefined && !isVisibility(body.visibility)) return c.json({ error: "invalid_visibility" }, 400);
  const startsAt = body.startsAt == null ? null : Number(body.startsAt);
  const endsAt = body.endsAt == null ? null : Number(body.endsAt);
  if ((startsAt != null && !Number.isFinite(startsAt)) || (endsAt != null && !Number.isFinite(endsAt)))
    return c.json({ error: "invalid_dates" }, 400);
  if (startsAt != null && endsAt != null && endsAt <= startsAt) return c.json({ error: "invalid_dates" }, 400);

  const db = c.var.db;
  const kind = body.kind;
  let values: typeof challenges.$inferInsert;
  let peakIds: number[] = [];
  const base = {
    id: newId(),
    creatorId: c.var.userId,
    title,
    description,
    visibility: (body.visibility as ChallengeRow["visibility"] | undefined) ?? "friends",
    startsAt: startsAt == null ? null : new Date(startsAt),
    endsAt: endsAt == null ? null : new Date(endsAt),
  };
  if (kind === "metric") {
    const allowed = ["elevation_gain", "distance", "summits", "unique_peaks", "activities", "active_weeks"] as const;
    if (!(allowed as readonly string[]).includes(body.metric as string)) return c.json({ error: "invalid_metric" }, 400);
    const target = Number(body.target);
    if (!Number.isFinite(target) || target <= 0 || target > 10_000_000) return c.json({ error: "invalid_target" }, 400);
    values = { ...base, kind, metric: body.metric as (typeof challengeMetricValues)[number], target };
  } else if (kind === "peaks") {
    if (!Array.isArray(body.peakIds) || !body.peakIds.every((p) => Number.isInteger(p)))
      return c.json({ error: "invalid_peaks" }, 400);
    peakIds = [...new Set(body.peakIds as number[])];
    if (peakIds.length < 1 || peakIds.length > MAX_PEAKS) return c.json({ error: "invalid_peaks" }, 400);
    const found = await db.select({ id: peaks.id }).from(peaks).where(inArray(peaks.id, peakIds));
    if (found.length !== peakIds.length) return c.json({ error: "invalid_peaks" }, 400);
    values = { ...base, kind };
  } else {
    return c.json({ error: "invalid_kind" }, 400);
  }

  const [row] = await db.insert(challenges).values(values).returning();
  if (peakIds.length) await db.insert(challengePeaks).values(peakIds.map((peakId) => ({ challengeId: row!.id, peakId })));
  await db.insert(challengeParticipants).values({ challengeId: row!.id, userId: c.var.userId });
  return c.json({ challenge: { ...toChallenge(row!), peakCount: kind === "peaks" ? peakIds.length : null } }, 201);
});

challengesRoutes.post("/:id/join", async (c) => {
  const row = await visibleChallenge(c, c.req.param("id"));
  if (!row) return c.json({ error: "not_found" }, 404);
  await c.var.db.insert(challengeParticipants).values({ challengeId: row.id, userId: c.var.userId }).onConflictDoNothing();
  return c.json({ joined: true });
});

challengesRoutes.delete("/:id/join", async (c) => {
  await c.var.db
    .delete(challengeParticipants)
    .where(and(eq(challengeParticipants.challengeId, c.req.param("id")), eq(challengeParticipants.userId, c.var.userId)));
  return c.json({ joined: false });
});

/** Borrar un reto propio. */
challengesRoutes.delete("/:id", async (c) => {
  const where = and(eq(challenges.id, c.req.param("id")), eq(challenges.creatorId, c.var.userId));
  const row = await c.var.db.select({ id: challenges.id }).from(challenges).where(where).get();
  if (!row) return c.json({ error: "not_found" }, 404);
  await c.var.db.delete(challenges).where(where);
  return c.body(null, 204);
});

