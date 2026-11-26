import { and, eq, inArray } from "drizzle-orm";
import type { Db } from "../db/client";
import { activities, ascents, peaks } from "../db/schema";

export type ActivityRow = typeof activities.$inferSelect;
export type AscentRow = typeof ascents.$inferSelect;

/** Resumen de actividad (sin ruta). La caja se omite para otros: podría delatar la zona de privacidad. */
export function toActivity(a: ActivityRow, opts: { includeBox: boolean } = { includeBox: true }) {
  return {
    id: a.id,
    userId: a.userId,
    source: a.source,
    sportType: a.sportType,
    title: a.title,
    startAt: a.startAt.getTime(),
    durationS: a.durationS,
    distanceM: a.distanceM,
    elevGainM: a.elevGainM,
    bbox:
      opts.includeBox && a.minLat != null
        ? { minLat: a.minLat, minLon: a.minLon, maxLat: a.maxLat, maxLon: a.maxLon }
        : null,
    visibility: a.visibility,
    createdAt: a.createdAt.getTime(),
  };
}

const peakColumns = { id: peaks.id, name: peaks.name, nameEs: peaks.nameEs, ele: peaks.ele, lat: peaks.lat, lon: peaks.lon };

export type PeakSummary = { id: number; name: string; nameEs: string | null; ele: number | null; lat: number; lon: number };

export function toAscent(a: AscentRow, peak: PeakSummary) {
  return {
    id: a.id,
    userId: a.userId,
    activityId: a.activityId,
    summitedAt: a.summitedAt.getTime(),
    note: a.note,
    visibility: a.visibility,
    peak,
  };
}

/** Ascensiones con su pico, según un filtro. */
export async function ascentsWithPeaks(db: Db, where: ReturnType<typeof and>) {
  const rows = await db
    .select({ ascent: ascents, peak: peakColumns })
    .from(ascents)
    .innerJoin(peaks, eq(ascents.peakId, peaks.id))
    .where(where)
    .orderBy(ascents.summitedAt);
  return rows.map((r) => toAscent(r.ascent, r.peak));
}

export async function ascentsForActivities(db: Db, activityIds: string[]) {
  if (activityIds.length === 0) return [];
  return ascentsWithPeaks(db, and(inArray(ascents.activityId, activityIds)));
}

export async function peaksById(db: Db, ids: number[]) {
  if (ids.length === 0) return new Map<number, PeakSummary>();
  const rows = await db.select(peakColumns).from(peaks).where(inArray(peaks.id, ids));
  return new Map(rows.map((p) => [p.id, p]));
}
