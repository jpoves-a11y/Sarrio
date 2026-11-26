import { isSunriseSummit, isSunsetSummit } from "../lib/sun";

// ---------------------------------------------------------------------------
// Historial del usuario (lo que necesitan las reglas)
// ---------------------------------------------------------------------------

export type HActivity = {
  id: string;
  startAt: number;
  durationS: number | null;
  distanceM: number | null;
  elevGainM: number | null;
  sportType: string;
};

export type HAscent = {
  id: string;
  activityId: string | null;
  peakId: number;
  summitedAt: number;
  ele: number | null;
  lat: number;
  lon: number;
  range: string | null;
};

export type History = { activities: HActivity[]; ascents: HAscent[] };

/** Deportes de montaña: cuentan para distancia, desnivel y constancia (además de cualquier actividad con cima). */
export const MOUNTAIN_SPORTS = new Set(["hiking", "mountaineering", "trail_running", "snowshoeing", "backcountry_skiing", "climbing"]);

// ---------------------------------------------------------------------------
// Fechas locales. Los usuarios son, de momento, de la península: los periodos
// (semanas, meses, estaciones) se cuentan en hora de Madrid.
// ---------------------------------------------------------------------------

export const TIME_ZONE = "Europe/Madrid";
const fmt = new Intl.DateTimeFormat("en-US", {
  timeZone: TIME_ZONE,
  year: "numeric",
  month: "numeric",
  day: "numeric",
  hour: "numeric",
  minute: "numeric",
  second: "numeric",
  hourCycle: "h23",
});

export type LocalDate = { y: number; m: number; d: number };

/** Fecha local (Madrid) de un instante. */
export function localDate(ms: number): LocalDate {
  const p = Object.fromEntries(fmt.formatToParts(new Date(ms)).map((x) => [x.type, x.value]));
  return { y: Number(p.year), m: Number(p.month), d: Number(p.day) };
}

function offsetAt(ms: number): number {
  const p = Object.fromEntries(fmt.formatToParts(new Date(ms)).map((x) => [x.type, x.value]));
  const asUtc = Date.UTC(Number(p.year), Number(p.month) - 1, Number(p.day), Number(p.hour), Number(p.minute), Number(p.second));
  return asUtc - Math.floor(ms / 1000) * 1000;
}

/** Instante en que empieza el día local y/m/d (admite meses y días fuera de rango, como Date.UTC). */
export function localMidnight(y: number, m: number, d: number): number {
  const guess = Date.UTC(y, m - 1, d);
  const first = guess - offsetAt(guess);
  return guess - offsetAt(first);
}

/** Número de día local desde 1970-01-01. */
const dayNumber = (ms: number) => {
  const { y, m, d } = localDate(ms);
  return Math.round(Date.UTC(y, m - 1, d) / 86_400_000);
};

/** Semana local (lunes a domingo) como número correlativo. 1970-01-01 fue jueves. */
export const weekIndex = (ms: number) => Math.floor((dayNumber(ms) + 3) / 7);

const mmdd = (ld: LocalDate) => ld.m * 100 + ld.d;

/** Estación astronómica aproximada: 0 primavera, 1 verano, 2 otoño, 3 invierno. */
export function season(ms: number): 0 | 1 | 2 | 3 {
  const v = mmdd(localDate(ms));
  if (v >= 321 && v <= 620) return 0;
  if (v >= 621 && v <= 922) return 1;
  if (v >= 923 && v <= 1220) return 2;
  return 3;
}

// ---------------------------------------------------------------------------
// Emblemas
// ---------------------------------------------------------------------------

export type Earned = { earnedAt: number; ascentId?: string; activityId?: string };
export type Progress = { value: number; target: number };
export type BadgeEvaluation = { earned: Map<string, Earned>; progress: Map<string, Progress> };

type Outing = { at: number; activityId?: string; ascentId?: string };

/**
 * Evalúa los 24 emblemas sobre el historial. Devuelve los conseguidos (con el momento y la
 * actividad o ascensión con que se ganaron) y el progreso de los que se pueden contar.
 */
export function evaluateBadges(history: History, now = Date.now()): BadgeEvaluation {
  const earned = new Map<string, Earned>();
  const progress = new Map<string, Progress>();
  const earn = (id: string, e: Earned) => {
    if (!earned.has(id)) earned.set(id, e);
  };

  const ascents = [...history.ascents].sort((a, b) => a.summitedAt - b.summitedAt);
  const withSummit = new Set(ascents.map((a) => a.activityId).filter(Boolean));
  const mountain = history.activities
    .filter((a) => MOUNTAIN_SPORTS.has(a.sportType) || withSummit.has(a.id))
    .sort((a, b) => a.startAt - b.startAt);
  const fromAscent = (a: HAscent): Earned => ({ earnedAt: a.summitedAt, ascentId: a.id, activityId: a.activityId ?? undefined });
  const fromActivity = (a: HActivity): Earned => ({ earnedAt: a.startAt, activityId: a.id });

  // Cimas distintas
  const unique = new Set<number>();
  const visits = new Map<number, number>();
  const ranges = new Set<string>();
  let maxEle = 0;
  const seasonsByYear = new Map<number, Set<number>>();
  for (const a of ascents) {
    unique.add(a.peakId);
    if (unique.size >= 1) earn("first-summit", fromAscent(a));
    if (unique.size >= 5) earn("peaks-5", fromAscent(a));
    if (unique.size >= 25) earn("peaks-25", fromAscent(a));
    if (unique.size >= 100) earn("peaks-100", fromAscent(a));

    const ele = a.ele ?? 0;
    maxEle = Math.max(maxEle, ele);
    if (ele >= 2000) earn("alt-2000", fromAscent(a));
    if (ele >= 3000) earn("alt-3000", fromAscent(a));
    if (ele >= 4000) earn("alt-4000", fromAscent(a));

    const n = (visits.get(a.peakId) ?? 0) + 1;
    visits.set(a.peakId, n);
    if (n >= 5) earn("faithful", fromAscent(a));

    if (a.range) {
      ranges.add(a.range);
      if (ranges.size >= 3) earn("explorer", fromAscent(a));
    }

    const year = localDate(a.summitedAt).y;
    const set = seasonsByYear.get(year) ?? new Set<number>();
    set.add(season(a.summitedAt));
    seasonsByYear.set(year, set);
    if (set.size === 4) earn("four-seasons", fromAscent(a));

    if (ele >= 2000 && season(a.summitedAt) === 3) earn("winter", fromAscent(a));
    if (isSunriseSummit(a.lat, a.lon, a.summitedAt)) earn("sunrise", fromAscent(a));
    if (isSunsetSummit(a.lat, a.lon, a.summitedAt)) earn("sunset", fromAscent(a));
  }
  progress.set("peaks-5", { value: unique.size, target: 5 });
  progress.set("peaks-25", { value: unique.size, target: 25 });
  progress.set("peaks-100", { value: unique.size, target: 100 });
  for (const t of [2000, 3000, 4000]) progress.set(`alt-${t}`, { value: Math.round(maxEle), target: t });
  progress.set("faithful", { value: Math.max(0, ...visits.values()), target: 5 });
  progress.set("explorer", { value: ranges.size, target: 3 });
  progress.set("four-seasons", { value: Math.max(0, ...[...seasonsByYear.values()].map((s) => s.size)), target: 4 });

  // Acumulados y esfuerzos de una actividad
  let gain = 0;
  let distance = 0;
  const gainByYear = new Map<number, number>();
  let bestGain = 0;
  let bestDistance = 0;
  for (const a of mountain) {
    const g = a.elevGainM ?? 0;
    const d = a.distanceM ?? 0;
    gain += g;
    distance += d;
    if (gain >= 10_000) earn("gain-10k", fromActivity(a));
    if (gain >= 88_490) earn("everest-10", fromActivity(a));
    if (distance >= 100_000) earn("km-100", fromActivity(a));
    if (distance >= 1_000_000) earn("km-1000", fromActivity(a));

    const year = localDate(a.startAt).y;
    const yg = (gainByYear.get(year) ?? 0) + g;
    gainByYear.set(year, yg);
    if (yg >= 8849) earn("everest", fromActivity(a));

    bestGain = Math.max(bestGain, g);
    bestDistance = Math.max(bestDistance, d);
    if (g >= 2000) earn("long-day", fromActivity(a));
    if (g >= 8849) earn("everesting", fromActivity(a));
    if (yg >= 100_000) earn("hundred-k", fromActivity(a));
    if (d >= 40_000) earn("ultra", fromActivity(a));
    if (g >= 1000 && d > 0 && d <= 5000) earn("vertical-km", fromActivity(a));
  }
  progress.set("gain-10k", { value: Math.round(gain), target: 10_000 });
  progress.set("everest-10", { value: Math.round(gain), target: 88_490 });
  progress.set("km-100", { value: Math.round(distance), target: 100_000 });
  progress.set("km-1000", { value: Math.round(distance), target: 1_000_000 });
  progress.set("everest", { value: Math.round(gainByYear.get(localDate(now).y) ?? 0), target: 8849 });
  progress.set("long-day", { value: Math.round(bestGain), target: 2000 });
  progress.set("everesting", { value: Math.round(bestGain), target: 8849 });
  progress.set("hundred-k", { value: Math.round(gainByYear.get(localDate(now).y) ?? 0), target: 100_000 });
  progress.set("ultra", { value: Math.round(bestDistance), target: 40_000 });

  // Encadenador: cimas por actividad
  const perActivity = new Map<string, HAscent[]>();
  for (const a of ascents) {
    if (!a.activityId) continue;
    const list = perActivity.get(a.activityId) ?? [];
    list.push(a);
    perActivity.set(a.activityId, list);
    if (list.length >= 3) earn("chain", fromAscent(a));
  }
  progress.set("chain", { value: Math.max(0, ...[...perActivity.values()].map((l) => l.length)), target: 3 });

  // Rachas de semanas con salida (actividades de montaña y ascensiones sueltas)
  const outings: Outing[] = [
    ...mountain.map((a) => ({ at: a.startAt, activityId: a.id })),
    ...ascents.filter((a) => !a.activityId).map((a) => ({ at: a.summitedAt, ascentId: a.id })),
  ].sort((a, b) => a.at - b.at);
  let prevWeek = Number.NaN;
  let run = 0;
  let bestRun = 0;
  for (const o of outings) {
    const w = weekIndex(o.at);
    if (w === prevWeek) continue;
    run = w === prevWeek + 1 ? run + 1 : 1;
    prevWeek = w;
    bestRun = Math.max(bestRun, run);
    const e = { earnedAt: o.at, activityId: o.activityId, ascentId: o.ascentId };
    if (run >= 4) earn("streak-4", e);
    if (run >= 12) earn("streak-12", e);
  }
  // La racha en curso solo sigue viva si la última salida fue esta semana o la anterior.
  const current = outings.length && weekIndex(now) - prevWeek <= 1 ? run : 0;
  progress.set("streak-4", { value: Math.max(current, Math.min(bestRun, 4)), target: 4 });
  progress.set("streak-12", { value: Math.max(current, Math.min(bestRun, 12)), target: 12 });

  // Logros de sí o no: no se enseña un progreso parcial (tu cima más alta no es «medio» Cuatromil)
  for (const id of BINARY_BADGES) progress.set(id, { value: earned.has(id) ? 1 : 0, target: 1 });

  return { earned, progress };
}

/** Emblemas que se consiguen de una vez (una cima, una actividad, un momento): progreso 0 / 1. */
export const BINARY_BADGES = [
  "first-summit",
  "alt-2000",
  "alt-3000",
  "alt-4000",
  "sunrise",
  "sunset",
  "winter",
  "chain",
  "long-day",
  "ultra",
  "vertical-km",
  "everesting",
];

// ---------------------------------------------------------------------------
// Retos
// ---------------------------------------------------------------------------

export type ChallengeDef = {
  kind: "metric" | "peaks";
  metric: string | null;
  target: number | null;
  sport: string | null;
  minEle: number | null;
  recurrence: "none" | "monthly" | "yearly";
  window: string | null;
  startsAt: number | null;
  endsAt: number | null;
  /** Solo en los de lista. */
  peakIds?: number[];
};

export type ChallengeProgress = {
  value: number;
  target: number;
  fraction: number;
  done: boolean;
  /** `upcoming`: el periodo aún no ha empezado (p. ej. un reto de verano en noviembre). */
  status: "active" | "upcoming" | "ended";
  periodStart: number | null;
  periodEnd: number | null;
  donePeakIds?: number[];
};

const parseMmdd = (s: string) => {
  const [m, d] = s.split("-").map(Number);
  return { m: m!, d: d! };
};

/** Periodo en curso (o el próximo, si ahora cae fuera de la ventana). `end` es exclusivo. */
export function challengePeriod(def: ChallengeDef, now: number): { start: number | null; end: number | null } {
  const today = localDate(now);
  if (def.recurrence === "monthly") {
    return { start: localMidnight(today.y, today.m, 1), end: localMidnight(today.y, today.m + 1, 1) };
  }
  if (def.recurrence === "yearly") {
    if (!def.window) return { start: localMidnight(today.y, 1, 1), end: localMidnight(today.y + 1, 1, 1) };
    const [fromS, toS] = def.window.split("..");
    const from = parseMmdd(fromS!);
    const to = parseMmdd(toS!);
    const wraps = to.m * 100 + to.d < from.m * 100 + from.d;
    const occurrences = [today.y - 1, today.y, today.y + 1].map((y) => ({
      start: localMidnight(y, from.m, from.d),
      end: localMidnight(wraps ? y + 1 : y, to.m, to.d + 1),
    }));
    return occurrences.find((o) => now >= o.start && now < o.end) ?? occurrences.find((o) => o.start > now)!;
  }
  return { start: def.startsAt, end: def.endsAt };
}

/** Progreso de un reto sobre el historial del usuario, en su periodo actual. */
export function challengeProgress(def: ChallengeDef, history: History, now = Date.now()): ChallengeProgress {
  const { start, end } = challengePeriod(def, now);
  const inPeriod = (ms: number) => (start == null || ms >= start) && (end == null || ms < end);
  const status: ChallengeProgress["status"] =
    start != null && now < start ? "upcoming" : end != null && now >= end ? "ended" : "active";

  const ascents = history.ascents.filter((a) => inPeriod(a.summitedAt));
  const finish = (value: number, target: number, extra: Partial<ChallengeProgress> = {}): ChallengeProgress => ({
    value,
    target,
    fraction: target > 0 ? Math.min(1, value / target) : 0,
    done: target > 0 && value >= target,
    status,
    periodStart: start,
    periodEnd: end,
    ...extra,
  });

  if (def.kind === "peaks") {
    const listed = new Set(def.peakIds ?? []);
    const done = [...new Set(ascents.filter((a) => listed.has(a.peakId)).map((a) => a.peakId))];
    return finish(done.length, listed.size, { donePeakIds: done });
  }

  const withSummit = new Set(history.ascents.map((a) => a.activityId).filter(Boolean));
  const activities = history.activities.filter(
    (a) =>
      inPeriod(a.startAt) &&
      (def.sport ? a.sportType === def.sport : MOUNTAIN_SPORTS.has(a.sportType) || withSummit.has(a.id)),
  );
  const target = def.target ?? 0;
  switch (def.metric) {
    case "elevation_gain":
      return finish(Math.round(activities.reduce((s, a) => s + (a.elevGainM ?? 0), 0)), target);
    case "max_activity_gain":
      // De sí o no: o tienes una actividad que llega, o no
      return finish(Math.max(0, ...activities.map((a) => a.elevGainM ?? 0)) >= target ? 1 : 0, 1);
    case "distance":
      return finish(Math.round(activities.reduce((s, a) => s + (a.distanceM ?? 0), 0)), target);
    case "activities":
      return finish(activities.length, target);
    case "active_weeks": {
      const weeks = new Set([
        ...activities.map((a) => weekIndex(a.startAt)),
        ...(def.sport ? [] : ascents.filter((a) => !a.activityId).map((a) => weekIndex(a.summitedAt))),
      ]);
      return finish(weeks.size, target);
    }
    case "summits":
      return finish(ascents.length, target);
    case "unique_peaks":
      return finish(new Set(ascents.map((a) => a.peakId)).size, target);
    case "high_summits":
      return finish(ascents.filter((a) => (a.ele ?? 0) >= (def.minEle ?? 0)).length, target);
    case "sunrise_summits":
      return finish(ascents.filter((a) => isSunriseSummit(a.lat, a.lon, a.summitedAt)).length, target);
    default:
      return finish(0, target);
  }
}

/**
 * Leyenda de lista de cimas (todos los tresmiles, todos los cuatromiles…): se gana con la
 * ascensión que completa la lista, contando siempre (sin periodo).
 */
export function evaluatePeakList(peakIds: number[], history: History): { earned: Earned | null; progress: Progress } {
  const listed = new Set(peakIds);
  const first = new Map<number, HAscent>();
  for (const a of [...history.ascents].sort((x, y) => x.summitedAt - y.summitedAt)) {
    if (listed.has(a.peakId) && !first.has(a.peakId)) first.set(a.peakId, a);
  }
  const progress = { value: first.size, target: listed.size };
  if (listed.size === 0 || first.size < listed.size) return { earned: null, progress };
  const last = [...first.values()].reduce((m, a) => (a.summitedAt > m.summitedAt ? a : m));
  return { earned: { earnedAt: last.summitedAt, ascentId: last.id, activityId: last.activityId ?? undefined }, progress };
}
