import { and, asc, eq, inArray, isNotNull, isNull, or } from "drizzle-orm";
import type { Db } from "../db/client";
import { activities, ascents, badges, challengeParticipants, challengePeaks, challenges, peaks, userBadges, users } from "../db/schema";
import { addFeedItem } from "./social";
import { challengeProgress, evaluateBadges, evaluatePeakList, type ChallengeDef, type History } from "./achievements";

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
  // Leyendas de lista: se ganan al completar su reto, aunque no te hayas unido
  const legends = await db
    .select({ id: challenges.id, badgeId: challenges.badgeId })
    .from(challenges)
    .where(and(isNotNull(challenges.badgeId), eq(challenges.kind, "peaks")));
  if (legends.length) {
    const peakMap = await peakIdsFor(db, legends.map((l) => l.id));
    for (const l of legends) {
      const r = evaluatePeakList(peakMap.get(l.id) ?? [], h);
      evaluation.progress.set(l.badgeId!, r.progress);
      if (r.earned && !evaluation.earned.has(l.badgeId!)) evaluation.earned.set(l.badgeId!, r.earned);
    }
  }
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
    // Al feed de mis amigos, con la visibilidad por defecto del usuario
    const visibility = await defaultVisibility(db, userId);
    for (const [badgeId, e] of fresh) {
      await addFeedItem(db, { actorId: userId, kind: "badge", refId: badgeId, visibility, at: e.earnedAt });
    }
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

async function defaultVisibility(db: Db, userId: string) {
  const u = await db.select({ v: users.defaultVisibility }).from(users).where(eq(users.id, userId)).get();
  return u?.v ?? "friends";
}

/**
 * Retos completados: todos los oficiales y los míos cuentan siempre (no hay que unirse). El
 * primero que se completa queda apuntado (`challenge_participants.completedAt`) y va al feed.
 */
export async function refreshChallenges(db: Db, userId: string, history: History) {
  const all = await db
    .select()
    .from(challenges)
    .where(or(isNull(challenges.creatorId), eq(challenges.creatorId, userId)));
  if (!all.length) return [];
  const ids = all.map((c) => c.id);
  const [peakMap, mine] = await Promise.all([
    peakIdsFor(db, ids),
    db
      .select()
      .from(challengeParticipants)
      .where(and(eq(challengeParticipants.userId, userId), inArray(challengeParticipants.challengeId, ids))),
  ]);
  const completedBefore = new Set(mine.filter((m) => m.completedAt).map((m) => m.challengeId));
  const completed: string[] = [];
  for (const challenge of all) {
    if (completedBefore.has(challenge.id)) continue;
    if (challengeProgress(toChallengeDef(challenge, peakMap.get(challenge.id)), history).done) completed.push(challenge.id);
  }
  if (!completed.length) return [];
  const now = new Date();
  const visibility = await defaultVisibility(db, userId);
  for (const challengeId of completed) {
    await db
      .insert(challengeParticipants)
      .values({ challengeId, userId, completedAt: now })
      .onConflictDoUpdate({ target: [challengeParticipants.challengeId, challengeParticipants.userId], set: { completedAt: now } });
    await addFeedItem(db, { actorId: userId, kind: "challenge_completed", refId: challengeId, visibility, at: now.getTime() });
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
