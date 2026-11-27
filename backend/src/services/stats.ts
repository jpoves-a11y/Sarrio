import { and, eq, gte, inArray, lt, ne } from "drizzle-orm";
import type { Db } from "../db/client";
import { activities, activityTracks, ascents, peaks } from "../db/schema";
import { haversine } from "../lib/geo";
import { decodeTrack } from "../lib/track";
import { localDate, localMidnight, MOUNTAIN_SPORTS, weekIndex } from "./achievements";

type Act = {
  id: string;
  startAt: number;
  durationS: number | null;
  distanceM: number | null;
  elevGainM: number | null;
  climbRateMh: number | null;
  sportType: string;
  title: string | null;
};
type Asc = {
  id: string;
  activityId: string | null;
  peakId: number;
  summitedAt: number;
  name: string;
  nameEs: string | null;
  ele: number | null;
  lat: number;
  lon: number;
};

/** Perfil de una cima para «Tu cordillera 3D»: toda la ruta con que se subió y dónde está la cumbre. */
export type PeakProfile = {
  activityId: string;
  date: number;
  /** 80 alturas de toda la ruta, muestreadas por distancia. */
  elevations: number[];
  /** Metros de toda la ruta. */
  totalDistance: number;
  /** Muestra más cercana a la cumbre. */
  summitIndex: number;
  /** Es la cima más alta de esa salida (se dibuja la ruta entera; las demás, subida y espejo). */
  isRouteTop: boolean;
  /** Metros y desnivel desde la salida hasta la cumbre. */
  distance: number;
  gain: number;
};

const PROFILE_SAMPLES = 80;

/** Perfil de una ruta muestreado por distancia, con la cumbre más cercana a (lat, lon). */
export function routeProfile(points: [number, number, number?, number?][], lat: number, lon: number) {
  const pts = points.filter((p) => p[2] != null);
  if (pts.length < 2) return null;
  const cum = [0];
  for (let i = 1; i < pts.length; i++) cum.push(cum[i - 1]! + haversine(pts[i - 1]![0], pts[i - 1]![1], pts[i]![0], pts[i]![1]));
  const total = cum[cum.length - 1]!;
  if (total <= 0) return null;
  // Punto de la ruta más cercano a la cima
  let best = 0, bestD = Infinity;
  pts.forEach((p, i) => {
    const d = haversine(p[0], p[1], lat, lon);
    if (d < bestD) { bestD = d; best = i; }
  });
  const elevations: number[] = [];
  let j = 0;
  for (let k = 0; k < PROFILE_SAMPLES; k++) {
    const target = (total * k) / (PROFILE_SAMPLES - 1);
    while (j < cum.length - 2 && cum[j + 1]! < target) j++;
    const span = cum[j + 1]! - cum[j]!;
    const t = span > 0 ? (target - cum[j]!) / span : 0;
    const e = pts[j]![2]! + (pts[j + 1]![2]! - pts[j]![2]!) * Math.min(1, Math.max(0, t));
    elevations.push(Math.round(e));
  }
  // Desnivel hasta la cumbre, con histéresis de 3 m para no sumar el ruido
  let gain = 0, ref = pts[0]![2]!;
  for (let i = 1; i <= best; i++) {
    const e = pts[i]![2]!;
    if (e - ref >= 3) { gain += e - ref; ref = e; } else if (ref - e >= 3) ref = e;
  }
  return {
    elevations,
    totalDistance: Math.round(total),
    summitIndex: Math.round((cum[best]! / total) * (PROFILE_SAMPLES - 1)),
    distance: Math.round(cum[best]!),
    gain: Math.round(gain),
  };
}

export type Totals = { gain: number; distance: number; durationS: number; activities: number; summits: number; uniquePeaks: number };

const dayOfYear = (ms: number) => {
  const d = localDate(ms);
  return Math.round((Date.UTC(d.y, d.m - 1, d.d) - Date.UTC(d.y, 0, 1)) / 86_400_000) + 1;
};
const isoDay = (ms: number) => {
  const d = localDate(ms);
  return `${d.y}-${String(d.m).padStart(2, "0")}-${String(d.d).padStart(2, "0")}`;
};

function totals(acts: Act[], ascs: Asc[]): Totals {
  return {
    gain: Math.round(acts.reduce((s, a) => s + (a.elevGainM ?? 0), 0)),
    distance: Math.round(acts.reduce((s, a) => s + (a.distanceM ?? 0), 0)),
    durationS: Math.round(acts.reduce((s, a) => s + (a.durationS ?? 0), 0)),
    activities: acts.length,
    summits: ascs.length,
    uniquePeaks: new Set(ascs.map((a) => a.peakId)).size,
  };
}

/** Desnivel acumulado a lo largo del año: puntos [día del año, metros acumulados]. */
function cumulative(acts: Act[]): number[][] {
  let sum = 0;
  return [...acts]
    .sort((a, b) => a.startAt - b.startAt)
    .filter((a) => (a.elevGainM ?? 0) > 0)
    .map((a) => {
      sum += a.elevGainM ?? 0;
      return [dayOfYear(a.startAt), Math.round(sum)];
    });
}

/** Datos de las salidas del usuario: todas las de montaña (o con cima) y sus ascensiones. */
async function load(db: Db, userId: string, opts: { onlyShared?: boolean } = {}) {
  const [actRows, ascRows] = await Promise.all([
    db
      .select({
        id: activities.id,
        startAt: activities.startAt,
        durationS: activities.durationS,
        distanceM: activities.distanceM,
        elevGainM: activities.elevGainM,
        climbRateMh: activities.climbRateMh,
        sportType: activities.sportType,
        title: activities.title,
      })
      .from(activities)
      .where(opts.onlyShared ? and(eq(activities.userId, userId), ne(activities.visibility, "private")) : eq(activities.userId, userId)),
    db
      .select({
        id: ascents.id,
        activityId: ascents.activityId,
        peakId: ascents.peakId,
        summitedAt: ascents.summitedAt,
        name: peaks.name,
        nameEs: peaks.nameEs,
        ele: peaks.ele,
        lat: peaks.lat,
        lon: peaks.lon,
      })
      .from(ascents)
      .innerJoin(peaks, eq(ascents.peakId, peaks.id))
      .where(opts.onlyShared ? and(eq(ascents.userId, userId), ne(ascents.visibility, "private")) : eq(ascents.userId, userId)),
  ]);
  const ascs: Asc[] = ascRows.map((a) => ({ ...a, summitedAt: a.summitedAt.getTime() }));
  const withSummit = new Set(ascs.map((a) => a.activityId).filter(Boolean));
  const acts: Act[] = actRows
    .map((a) => ({ ...a, startAt: a.startAt.getTime() }))
    .filter((a) => MOUNTAIN_SPORTS.has(a.sportType) || withSummit.has(a.id));
  return { acts, ascs };
}

/**
 * Estadísticas del perfil: de un año (`year`) o de siempre (`null`). Los periodos van en hora de
 * Madrid, como emblemas y retos.
 */
export async function userStats(db: Db, userId: string, year: number | null) {
  const { acts, ascs } = await load(db, userId);
  const yearOf = (ms: number) => localDate(ms).y;
  const inYear = <T>(list: T[], at: (x: T) => number, y: number) => list.filter((x) => yearOf(at(x)) === y);

  const years = [...new Set([...acts.map((a) => yearOf(a.startAt)), ...ascs.map((a) => yearOf(a.summitedAt))])].sort((a, b) => b - a);
  const periodActs = year == null ? acts : inYear(acts, (a) => a.startAt, year);
  const periodAscs = year == null ? ascs : inYear(ascs, (a) => a.summitedAt, year);
  const prevActs = year == null ? [] : inYear(acts, (a) => a.startAt, year - 1);
  const prevAscs = year == null ? [] : inYear(ascs, (a) => a.summitedAt, year - 1);

  // Por mes (o por año, en «siempre»)
  const monthly = Array.from({ length: 12 }, (_, i) => ({ month: i + 1, gain: 0, distance: 0, activities: 0 }));
  for (const a of periodActs) {
    const m = monthly[localDate(a.startAt).m - 1]!;
    m.gain += Math.round(a.elevGainM ?? 0);
    m.distance += Math.round(a.distanceM ?? 0);
    m.activities += 1;
  }
  const yearly = years
    .slice()
    .sort((a, b) => a - b)
    .map((y) => {
      const list = inYear(acts, (a) => a.startAt, y);
      return { year: y, gain: Math.round(list.reduce((s, a) => s + (a.elevGainM ?? 0), 0)), activities: list.length };
    });

  // Calendario: día → desnivel y salidas (las 53 semanas del año, o el último año en «siempre»)
  const calStart = year == null ? Date.now() - 371 * 86_400_000 : localMidnight(year, 1, 1);
  const calEnd = year == null ? Date.now() + 86_400_000 : localMidnight(year + 1, 1, 1);
  const days = new Map<string, { date: string; gain: number; activityIds: string[] }>();
  for (const a of acts.filter((a) => a.startAt >= calStart && a.startAt < calEnd)) {
    const key = isoDay(a.startAt);
    const d = days.get(key) ?? { date: key, gain: 0, activityIds: [] };
    d.gain += Math.round(a.elevGainM ?? 0);
    d.activityIds.push(a.id);
    days.set(key, d);
  }

  // Rachas de semanas con salida (de siempre: la racha no entiende de años)
  const weeks = [...new Set(acts.map((a) => weekIndex(a.startAt)))].sort((a, b) => a - b);
  let best = 0, run = 0, prev = Number.NaN;
  for (const w of weeks) {
    run = w === prev + 1 ? run + 1 : 1;
    best = Math.max(best, run);
    prev = w;
  }
  const current = weeks.length && weekIndex(Date.now()) - prev <= 1 ? run : 0;

  // Récords del periodo
  const maxBy = (list: Act[], f: (a: Act) => number | null) =>
    list.reduce<Act | null>((m, a) => ((f(a) ?? 0) > ((m && f(m)) ?? 0) ? a : m), null);
  const rec = (a: Act | null, f: (a: Act) => number | null) =>
    a && (f(a) ?? 0) > 0 ? { value: Math.round(f(a)!), activityId: a.id, date: a.startAt, title: a.title } : null;
  const highest = periodAscs.reduce<Asc | null>((m, a) => ((a.ele ?? 0) > (m?.ele ?? 0) ? a : m), null);

  // Cimas únicas de siempre (para «Tu cordillera 3D»), con el perfil de su última subida con ruta
  const byPeak = new Map<number, { id: number; name: string; ele: number | null; count: number; last: number; profile: PeakProfile | null }>();
  for (const a of ascs) {
    const p = byPeak.get(a.peakId) ?? { id: a.peakId, name: a.nameEs ?? a.name, ele: a.ele, count: 0, last: 0, profile: null };
    p.count += 1;
    p.last = Math.max(p.last, a.summitedAt);
    byPeak.set(a.peakId, p);
  }
  const latestWithRoute = new Map<number, Asc>();
  for (const a of ascs) {
    if (!a.activityId) continue;
    const prev = latestWithRoute.get(a.peakId);
    if (!prev || a.summitedAt > prev.summitedAt) latestWithRoute.set(a.peakId, a);
  }
  const neededActivities = [...new Set([...latestWithRoute.values()].map((a) => a.activityId!))];
  if (neededActivities.length) {
    const tracks = await db.select().from(activityTracks).where(inArray(activityTracks.activityId, neededActivities));
    const decoded = new Map<string, Awaited<ReturnType<typeof decodeTrack>>>();
    for (const t of tracks) decoded.set(t.activityId, await decodeTrack(t.data));
    for (const [peakId, a] of latestWithRoute) {
      const points = decoded.get(a.activityId!);
      if (!points) continue;
      const prof = routeProfile(points as [number, number, number?, number?][], a.lat, a.lon);
      if (!prof) continue;
      const sameRoute = ascs.filter((x) => x.activityId === a.activityId);
      const isRouteTop = sameRoute.every((x) => (x.ele ?? 0) <= (a.ele ?? 0));
      byPeak.get(peakId)!.profile = { activityId: a.activityId!, date: a.summitedAt, isRouteTop, ...prof };
    }
  }

  return {
    year,
    years,
    totals: totals(periodActs, periodAscs),
    previousTotals: year == null ? null : totals(prevActs, prevAscs),
    cumulative: year == null ? null : { current: cumulative(periodActs), previous: cumulative(prevActs) },
    monthly,
    yearly,
    calendar: { start: isoDay(calStart), days: [...days.values()] },
    streak: { current, best },
    records: {
      gain: rec(maxBy(periodActs, (a) => a.elevGainM), (a) => a.elevGainM),
      distance: rec(maxBy(periodActs, (a) => a.distanceM), (a) => a.distanceM),
      duration: rec(maxBy(periodActs, (a) => a.durationS), (a) => a.durationS),
      climbRate: rec(maxBy(periodActs, (a) => a.climbRateMh), (a) => a.climbRateMh),
      highestPeak: highest
        ? { name: highest.nameEs ?? highest.name, ele: highest.ele, date: highest.summitedAt, activityId: highest.activityId, peakId: highest.peakId }
        : null,
    },
    climbRates: periodActs
      .filter((a) => a.climbRateMh != null)
      .sort((a, b) => a.startAt - b.startAt)
      .map((a) => ({ date: a.startAt, value: Math.round(a.climbRateMh!), activityId: a.id })),
    peaks: [...byPeak.values()].sort((a, b) => (a.ele ?? 0) - (b.ele ?? 0)),
  };
}

export type LeaderMetric = "gain" | "summits" | "distance";

/** Clasificación del mes en curso entre mis amigos y yo (solo lo que no es privado). */
export async function monthlyLeaderboard(db: Db, userIds: string[], metric: LeaderMetric, now = Date.now()) {
  const today = localDate(now);
  const from = localMidnight(today.y, today.m, 1);
  const to = localMidnight(today.y, today.m + 1, 1);
  if (!userIds.length) return { from, to, rows: [] as { userId: string; value: number }[] };
  const [actRows, ascRows] = await Promise.all([
    db
      .select({ userId: activities.userId, gain: activities.elevGainM, distance: activities.distanceM, sport: activities.sportType, id: activities.id })
      .from(activities)
      .where(and(inArray(activities.userId, userIds), ne(activities.visibility, "private"), gte(activities.startAt, new Date(from)), lt(activities.startAt, new Date(to)))),
    db
      .select({ userId: ascents.userId, activityId: ascents.activityId })
      .from(ascents)
      .where(and(inArray(ascents.userId, userIds), ne(ascents.visibility, "private"), gte(ascents.summitedAt, new Date(from)), lt(ascents.summitedAt, new Date(to)))),
  ]);
  const withSummit = new Set(ascRows.map((a) => a.activityId).filter(Boolean));
  const value = new Map(userIds.map((id) => [id, 0]));
  if (metric === "summits") {
    for (const a of ascRows) value.set(a.userId, (value.get(a.userId) ?? 0) + 1);
  } else {
    for (const a of actRows) {
      if (!MOUNTAIN_SPORTS.has(a.sport) && !withSummit.has(a.id)) continue;
      const v = metric === "gain" ? a.gain ?? 0 : a.distance ?? 0;
      value.set(a.userId, (value.get(a.userId) ?? 0) + v);
    }
  }
  const rows = [...value.entries()].map(([userId, v]) => ({ userId, value: Math.round(v) })).sort((a, b) => b.value - a.value);
  return { from, to, rows };
}

export { load as loadUserMountainData };
