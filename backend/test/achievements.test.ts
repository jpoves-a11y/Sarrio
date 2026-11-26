import { describe, expect, it } from "vitest";
import {
  challengePeriod,
  challengeProgress,
  evaluateBadges,
  localMidnight,
  season,
  weekIndex,
  type ChallengeDef,
  type HActivity,
  type HAscent,
} from "../src/services/achievements";
import { isSunriseSummit, isSunsetSummit, sunElevation } from "../src/lib/sun";

const H = 3_600_000;
const D = 24 * H;
let n = 0;
const act = (startAt: number, o: Partial<HActivity> = {}): HActivity => ({
  id: `a${++n}`,
  startAt,
  durationS: 3600,
  distanceM: 10_000,
  elevGainM: 800,
  sportType: "hiking",
  ...o,
});
const asc = (summitedAt: number, o: Partial<HAscent> = {}): HAscent => ({
  id: `s${++n}`,
  activityId: null,
  peakId: 1,
  summitedAt,
  ele: 2500,
  lat: 42.63,
  lon: 0.65,
  range: "Pirineos",
  ...o,
});
const metric = (o: Partial<ChallengeDef>): ChallengeDef => ({
  kind: "metric",
  metric: "elevation_gain",
  target: 1000,
  sport: null,
  minEle: null,
  recurrence: "none",
  window: null,
  startsAt: null,
  endsAt: null,
  ...o,
});

describe("sun", () => {
  it("is high at solar noon in summer and below the horizon at midnight", () => {
    expect(sunElevation(42.63, 0.65, Date.UTC(2026, 5, 21, 12))).toBeGreaterThan(65);
    expect(sunElevation(42.63, 0.65, Date.UTC(2026, 5, 21, 0))).toBeLessThan(-15);
  });
  it("classifies sunrise and sunset summits", () => {
    // Amanecer en el Aneto el 14/07 ≈ 04:35 UTC
    expect(isSunriseSummit(42.63, 0.65, Date.UTC(2026, 6, 14, 4, 50))).toBe(true);
    expect(isSunriseSummit(42.63, 0.65, Date.UTC(2026, 6, 14, 9))).toBe(false);
    // Puesta ≈ 19:30 UTC
    expect(isSunsetSummit(42.63, 0.65, Date.UTC(2026, 6, 14, 19, 50))).toBe(true);
    expect(isSunsetSummit(42.63, 0.65, Date.UTC(2026, 6, 14, 4, 0))).toBe(false);
  });
});

describe("local dates", () => {
  it("uses Madrid midnight and Monday weeks", () => {
    expect(localMidnight(2026, 1, 1)).toBe(Date.UTC(2025, 11, 31, 23));
    expect(localMidnight(2026, 7, 1)).toBe(Date.UTC(2026, 5, 30, 22));
    // Lunes 23/11/2026 y domingo 29/11/2026 en la misma semana; lunes 30 en la siguiente
    const mon = weekIndex(Date.UTC(2026, 10, 23, 10));
    expect(weekIndex(Date.UTC(2026, 10, 29, 20))).toBe(mon);
    expect(weekIndex(Date.UTC(2026, 10, 30, 10))).toBe(mon + 1);
  });
  it("knows the seasons", () => {
    expect(season(Date.UTC(2026, 3, 10))).toBe(0);
    expect(season(Date.UTC(2026, 6, 10))).toBe(1);
    expect(season(Date.UTC(2026, 9, 10))).toBe(2);
    expect(season(Date.UTC(2026, 0, 10))).toBe(3);
    expect(season(Date.UTC(2026, 11, 25))).toBe(3);
  });
});

describe("evaluateBadges", () => {
  it("awards summit, altitude and momentary badges with the ascent that earned them", () => {
    const a1 = asc(Date.UTC(2026, 6, 14, 9), { peakId: 1, ele: 3404 });
    const a2 = asc(Date.UTC(2026, 6, 20, 9), { peakId: 2, ele: 1800, range: "Sierra Nevada" });
    const { earned, progress } = evaluateBadges({ activities: [], ascents: [a2, a1] });
    expect(earned.get("first-summit")?.ascentId).toBe(a1.id);
    expect(earned.get("alt-3000")?.ascentId).toBe(a1.id);
    expect(earned.has("alt-4000")).toBe(false);
    expect(progress.get("alt-4000")).toEqual({ value: 3404, target: 4000 });
    expect(progress.get("peaks-5")).toEqual({ value: 2, target: 5 });
    expect(progress.get("explorer")).toEqual({ value: 2, target: 3 });
  });

  it("awards winter, faithful and four seasons", () => {
    const year = [Date.UTC(2026, 0, 15, 11), Date.UTC(2026, 3, 15, 11), Date.UTC(2026, 6, 15, 11), Date.UTC(2026, 9, 15, 11), Date.UTC(2026, 10, 1, 11)];
    const list = year.map((t) => asc(t, { peakId: 7 }));
    const { earned } = evaluateBadges({ activities: [], ascents: list });
    expect(earned.get("winter")?.ascentId).toBe(list[0]!.id);
    expect(earned.get("four-seasons")?.ascentId).toBe(list[3]!.id);
    expect(earned.get("faithful")?.ascentId).toBe(list[4]!.id);
  });

  it("accumulates gain and distance only from mountain outings", () => {
    const acts = [
      act(Date.UTC(2026, 1, 1), { elevGainM: 6000, distanceM: 60_000 }),
      act(Date.UTC(2026, 2, 1), { elevGainM: 50_000, sportType: "cycling", distanceM: 900_000 }),
      act(Date.UTC(2026, 3, 1), { elevGainM: 4000, distanceM: 45_000 }),
    ];
    const { earned, progress } = evaluateBadges({ activities: acts, ascents: [] });
    expect(earned.get("gain-10k")?.activityId).toBe(acts[2]!.id);
    expect(earned.get("everest")?.activityId).toBe(acts[2]!.id);
    expect(earned.get("km-100")?.activityId).toBe(acts[2]!.id);
    expect(earned.get("long-day")?.activityId).toBe(acts[0]!.id);
    expect(earned.get("ultra")?.activityId).toBe(acts[0]!.id);
    expect(earned.has("km-1000")).toBe(false);
    expect(progress.get("km-1000")?.value).toBe(105_000);
  });

  it("only counts the everest within one calendar year", () => {
    const acts = [act(Date.UTC(2025, 11, 1), { elevGainM: 5000 }), act(Date.UTC(2026, 0, 10), { elevGainM: 5000 })];
    expect(evaluateBadges({ activities: acts, ascents: [] }).earned.has("everest")).toBe(false);
  });

  it("detects a vertical kilometre and a chain of summits", () => {
    const vk = act(Date.UTC(2026, 4, 1), { elevGainM: 1010, distanceM: 4800, sportType: "trail_running" });
    const chain = act(Date.UTC(2026, 4, 2));
    const s = [1, 2, 3].map((p) => asc(Date.UTC(2026, 4, 2, 8 + p), { peakId: p, activityId: chain.id }));
    const { earned } = evaluateBadges({ activities: [vk, chain], ascents: s });
    expect(earned.get("vertical-km")?.activityId).toBe(vk.id);
    expect(earned.get("chain")?.ascentId).toBe(s[2]!.id);
  });

  it("counts consecutive weeks", () => {
    const start = Date.UTC(2026, 8, 7, 9); // lunes
    const weekly = [0, 1, 2, 3].map((w) => act(start + w * 7 * D + (w % 2) * 3 * D));
    const { earned } = evaluateBadges({ activities: weekly, ascents: [] });
    expect(earned.get("streak-4")?.activityId).toBe(weekly[3]!.id);

    const broken = [0, 1, 3, 4].map((w) => act(start + w * 7 * D));
    const res = evaluateBadges({ activities: broken, ascents: [] }, start + 4 * 7 * D);
    expect(res.earned.has("streak-4")).toBe(false);
    expect(res.progress.get("streak-4")?.value).toBe(2);
  });
});

describe("challenges", () => {
  const now = Date.UTC(2026, 10, 26, 12);

  it("computes monthly and yearly periods", () => {
    expect(challengePeriod(metric({ recurrence: "monthly" }), now)).toEqual({
      start: Date.UTC(2026, 9, 31, 23),
      end: Date.UTC(2026, 10, 30, 23),
    });
    expect(challengePeriod(metric({ recurrence: "yearly" }), now).start).toBe(Date.UTC(2025, 11, 31, 23));
  });

  it("picks the upcoming window when outside it, and the current one across new year", () => {
    const summer = challengePeriod(metric({ recurrence: "yearly", window: "06-21..09-22" }), now);
    expect(summer.start).toBe(Date.UTC(2027, 5, 20, 22));
    expect(summer.end).toBe(Date.UTC(2027, 8, 22, 22));
    const winter = challengePeriod(metric({ recurrence: "yearly", window: "12-21..03-20" }), Date.UTC(2027, 0, 10));
    expect(winter.start).toBe(Date.UTC(2026, 11, 20, 23));
    expect(winter.end).toBe(Date.UTC(2027, 2, 20, 23));
  });

  it("sums the metric within the period and filters by sport", () => {
    const history = {
      activities: [
        act(Date.UTC(2026, 10, 3), { elevGainM: 1200, sportType: "trail_running" }),
        act(Date.UTC(2026, 10, 10), { elevGainM: 900 }),
        act(Date.UTC(2026, 9, 10), { elevGainM: 5000 }),
      ],
      ascents: [],
    };
    const month = challengeProgress(metric({ recurrence: "monthly", target: 2000 }), history, now);
    expect(month).toMatchObject({ value: 2100, target: 2000, done: true, status: "active" });
    const trail = challengeProgress(metric({ recurrence: "monthly", sport: "trail_running", target: 2000 }), history, now);
    expect(trail).toMatchObject({ value: 1200, done: false });
    expect(trail.fraction).toBeCloseTo(0.6);
    const summer = challengeProgress(metric({ recurrence: "yearly", window: "06-21..09-22" }), history, now);
    expect(summer.status).toBe("upcoming");
  });

  it("tracks peak lists", () => {
    const def: ChallengeDef = { ...metric({}), kind: "peaks", metric: null, target: null, peakIds: [1, 2, 3] };
    const p = challengeProgress(def, { activities: [], ascents: [asc(now - D, { peakId: 2 }), asc(now - D, { peakId: 2 }), asc(now, { peakId: 9 })] }, now);
    expect(p).toMatchObject({ value: 1, target: 3, done: false, donePeakIds: [2] });
  });

  it("counts high summits and active weeks", () => {
    const history = {
      activities: [act(Date.UTC(2026, 10, 2, 9)), act(Date.UTC(2026, 10, 4, 9)), act(Date.UTC(2026, 10, 12, 9))],
      ascents: [asc(Date.UTC(2026, 10, 2, 11), { ele: 3100 }), asc(Date.UTC(2026, 10, 3, 11), { ele: 2900 })],
    };
    expect(challengeProgress(metric({ recurrence: "monthly", metric: "active_weeks", target: 4 }), history, now).value).toBe(2);
    expect(challengeProgress(metric({ recurrence: "monthly", metric: "high_summits", minEle: 3000, target: 5 }), history, now).value).toBe(1);
  });
});
