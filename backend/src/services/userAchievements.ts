import { and, asc, eq, inArray, isNull } from "drizzle-orm";
import type { Db } from "../db/client";
import { activities, ascents, badges, challengeParticipants, challengePeaks, challenges, peaks, userBadges } from "../db/schema";
import { challengeProgress, evaluateBadges, type ChallengeDef, type History } from "./achievements";

export type ChallengeRow = typeof challenges.$inferSelect;

/** Todo lo que las reglas necesitan del usuario: actividades (sin ruta) y ascensiones con su pico. */
export async function loadHistory(db: Db, userId: string): Promise<History> {
  const [acts, asc_] = await Promise.all([
    db
      .select({
        id: activities.id,
        startAt: activities.startAt,
        durationS: activities.durationS,
        distanceM: activities.distanceM,
        elevGainM: activities.elevGainM,
        sportType: activities.sportType,
      })
      .from(activities)
      .where(eq(activities.userId, userId)),
    db
      .select({
        id: ascents.id,
        activityId: ascents.activityId,
        peakId: ascents.peakId,
        summitedAt: ascents.summitedAt,
        ele: peaks.ele,
        lat: peaks.lat,
        lon: peaks.lon,
        range: peaks.range,
      })
      .from(ascents)
      .innerJoin(peaks, eq(ascents.peakId, peaks.id))
      .where(eq(ascents.userId, userId)),
  ]);
  return {
    activities: acts.map((a) => ({ ...a, startAt: a.startAt.getTime() })),
    ascents: asc_.map((a) => ({ ...a, summitedAt: a.summitedAt.getTime() })),
  };
}

/**
 * Evalúa los emblemas y guarda los nuevos. Los emblemas no se retiran: si luego se borra la
 * actividad, el emblema se queda. Devuelve los ids recién conseguidos y la evaluación completa.
 */
export async function awardBadges(db: Db, userId: string, history?: History) {
  const h = history ?? (await loadHistory(db, userId));
  const evaluation = evaluateBadges(h);
  const stored = await db.select({ badgeId: userBadges.badgeId }).from(userBadges).where(eq(userBadges.userId, userId));
  const have = new Set(stored.map((s) => s.badgeId));
  const fresh = [...evaluation.earned.entries()].filter(([id]) => !have.has(id));
  if (fresh.length) {
    await db
      .insert(userBadges)
      .values(
        fresh.map(([badgeId, e]) => ({
          userId,
          badgeId,
          ascentId: e.ascentId ?? null,
          activityId: e.activityId ?? null,
          earnedAt: new Date(e.earnedAt),
        })),
      )
      .onConflictDoNothing();
  }
  return { newBadgeIds: fresh.map(([id]) => id), evaluation, history: h };
}

export function toChallengeDef(c: ChallengeRow, peakIds?: number[]): ChallengeDef {
  return {
    kind: c.kind,
    metric: c.metric,
    target: c.target,
    sport: c.sport,
    minEle: c.minEle,
    recurrence: c.recurrence,
    window: c.window,
    startsAt: c.startsAt?.getTime() ?? null,
    endsAt: c.endsAt?.getTime() ?? null,
    peakIds,
  };
}

export async function peakIdsFor(db: Db, challengeIds: string[]) {
  const map = new Map<string, number[]>();
  if (!challengeIds.length) return map;
  const rows = await db
    .select({ challengeId: challengePeaks.challengeId, peakId: challengePeaks.peakId })
    .from(challengePeaks)
    .where(inArray(challengePeaks.challengeId, challengeIds));
  for (const r of rows) map.set(r.challengeId, [...(map.get(r.challengeId) ?? []), r.peakId]);
  return map;
}

/** Marca como completados los retos a los que está unido el usuario y ya ha cumplido. */
export async function refreshChallenges(db: Db, userId: string, history: History) {
  const joined = await db
    .select({ challenge: challenges })
    .from(challengeParticipants)
    .innerJoin(challenges, eq(challengeParticipants.challengeId, challenges.id))
    .where(and(eq(challengeParticipants.userId, userId), isNull(challengeParticipants.completedAt)));
  if (!joined.length) return [];
  const ids = joined.map((j) => j.challenge.id);
  const peakMap = await peakIdsFor(db, ids);
  const completed: string[] = [];
  for (const { challenge } of joined) {
    const p = challengeProgress(toChallengeDef(challenge, peakMap.get(challenge.id)), history);
    if (p.done) completed.push(challenge.id);
  }
  if (completed.length) {
    await db
      .update(challengeParticipants)
      .set({ completedAt: new Date() })
      .where(and(eq(challengeParticipants.userId, userId), inArray(challengeParticipants.challengeId, completed)));
  }
  return completed;
}

/** Tras una subida: emblemas nuevos (con su ficha) y retos completados. */
export async function afterUpload(db: Db, userId: string) {
  const { newBadgeIds, history } = await awardBadges(db, userId);
  await refreshChallenges(db, userId, history);
  if (!newBadgeIds.length) return [];
  const rows = await db.select().from(badges).where(inArray(badges.id, newBadgeIds)).orderBy(asc(badges.sortOrder));
  return rows.map((b) => ({ id: b.id, name: b.name, description: b.description, tier: b.tier, category: b.category, icon: b.icon }));
}
