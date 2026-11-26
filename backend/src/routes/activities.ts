import { and, desc, eq, lt } from "drizzle-orm";
import { Hono } from "hono";
import { bodyLimit } from "hono/body-limit";
import type { AppBindings } from "../env";
import { requireAuth } from "../auth/session";
import { activities, activityTracks, ascents, privacyZones, providerConnections, users, type Source, type Visibility } from "../db/schema";
import { applyPrivacyZones } from "../lib/geo";
import { newId } from "../lib/ids";
import { boundingBox, decodeTrack, encodeTrack, parseTrack, serializeSegments, trackReaches } from "../lib/track";
import { isVisibility } from "../lib/validation";
import { ascentsForActivities, peaksById, toActivity, toAscent } from "../services/activities";
import { getRelationship } from "../services/relationships";
import { canView, mustTrimTrack } from "../services/visibility";

export const activitiesRoutes = new Hono<AppBindings>();
activitiesRoutes.use("*", requireAuth);

/** Fuentes que la app puede subir (Polar solo con la cuenta de Polar conectada). */
const uploadSources = ["healthkit", "file", "manual", "polar"] as const satisfies readonly Source[];
const SPORT_RE = /^[a-z_]{2,30}$/;
const MAX_ASCENTS_PER_ACTIVITY = 50;

const isNum = (v: unknown): v is number => typeof v === "number" && Number.isFinite(v);
const optNum = (v: unknown) => v === undefined || v === null || (isNum(v) && v >= 0);

/**
 * Sube una actividad con su ruta y las cumbres que la app ha detectado.
 * Es idempotente por (usuario, fuente, externalId): repetir la subida devuelve la existente.
 * Cada cumbre se comprueba contra la ruta; las que la ruta no respalda se descartan.
 */
activitiesRoutes.post("/", bodyLimit({ maxSize: 4 * 1024 * 1024 }), async (c) => {
  const body = await c.req.json<Record<string, any>>().catch(() => null);
  if (!body || typeof body !== "object") return c.json({ error: "invalid_body" }, 400);

  const { source, externalId, sportType, title, startAt, durationS, distanceM, elevGainM } = body;
  if (!(uploadSources as readonly string[]).includes(source)) return c.json({ error: "invalid_source" }, 400);
  if (typeof externalId !== "string" || externalId.length < 1 || externalId.length > 200)
    return c.json({ error: "invalid_external_id" }, 400);
  if (typeof sportType !== "string" || !SPORT_RE.test(sportType)) return c.json({ error: "invalid_sport" }, 400);
  if (title != null && (typeof title !== "string" || title.length > 120)) return c.json({ error: "invalid_title" }, 400);
  if (!isNum(startAt) || startAt < 0) return c.json({ error: "invalid_start" }, 400);
  if (!optNum(durationS) || !optNum(distanceM) || !optNum(elevGainM)) return c.json({ error: "invalid_stats" }, 400);
  if (body.visibility !== undefined && !isVisibility(body.visibility)) return c.json({ error: "invalid_visibility" }, 400);

  const track = body.track === undefined || body.track === null ? [] : parseTrack(body.track);
  if (!track) return c.json({ error: "invalid_track" }, 400);

  const rawAscents: unknown[] = Array.isArray(body.ascents) ? body.ascents : [];
  if (rawAscents.length > MAX_ASCENTS_PER_ACTIVITY) return c.json({ error: "too_many_ascents" }, 400);
  const wanted = new Map<number, number>();
  for (const a of rawAscents as Record<string, unknown>[]) {
    if (!a || !Number.isInteger(a.peakId) || !isNum(a.summitedAt)) return c.json({ error: "invalid_ascent" }, 400);
    if (!wanted.has(a.peakId as number)) wanted.set(a.peakId as number, a.summitedAt as number);
  }

  const db = c.var.db;
  const userId = c.var.userId;

  if (source === "polar") {
    const linked = await db
      .select({ userId: providerConnections.userId })
      .from(providerConnections)
      .where(and(eq(providerConnections.userId, userId), eq(providerConnections.provider, "polar")))
      .get();
    if (!linked) return c.json({ error: "polar_not_connected" }, 409);
  }

  const existing = await db
    .select()
    .from(activities)
    .where(and(eq(activities.userId, userId), eq(activities.source, source), eq(activities.externalId, externalId)))
    .get();
  if (existing) {
    return c.json({ activity: toActivity(existing), ascents: await ascentsForActivities(db, [existing.id]), created: false });
  }

  const user = await db.select({ defaultVisibility: users.defaultVisibility }).from(users).where(eq(users.id, userId)).get();
  if (!user) return c.json({ error: "unauthorized" }, 401);
  const visibility: Visibility = body.visibility ?? user.defaultVisibility;

  // Solo cumbres de picos reales por los que pasa la ruta.
  const peakMap = await peaksById(db, [...wanted.keys()]);
  const verified = [...wanted.entries()].filter(([peakId]) => {
    const peak = peakMap.get(peakId);
    return peak && track.length > 0 && trackReaches(track, peak.lat, peak.lon);
  });

  const box = boundingBox(track);
  const activityId = newId();
  const [activity] = await db
    .insert(activities)
    .values({
      id: activityId,
      userId,
      source,
      externalId,
      sportType,
      title: typeof title === "string" ? title.trim() || null : null,
      startAt: new Date(startAt),
      durationS: durationS == null ? null : Math.round(durationS),
      distanceM: distanceM ?? null,
      elevGainM: elevGainM ?? null,
      minLat: box?.minLat,
      minLon: box?.minLon,
      maxLat: box?.maxLat,
      maxLon: box?.maxLon,
      visibility,
    })
    .returning();

  if (track.length > 0) {
    const data = await encodeTrack(track);
    await db.insert(activityTracks).values({ activityId, pointCount: track.length, data: Buffer.from(data) });
  }

  const inserted = verified.length
    ? await db
        .insert(ascents)
        .values(
          verified.map(([peakId, summitedAt]) => ({
            id: newId(),
            userId,
            peakId,
            activityId,
            summitedAt: new Date(summitedAt),
            visibility,
          })),
        )
        .returning()
    : [];

  return c.json(
    {
      activity: toActivity(activity!),
      ascents: inserted.map((a) => toAscent(a, peakMap.get(a.peakId)!)),
      created: true,
      rejectedPeakIds: [...wanted.keys()].filter((id) => !verified.some(([v]) => v === id)),
    },
    201,
  );
});

/** Mis actividades, de la más reciente a la más antigua. Paginación con `?before=<ms>`. */
activitiesRoutes.get("/", async (c) => {
  const limit = Math.min(Math.max(Number(c.req.query("limit")) || 50, 1), 200);
  const before = Number(c.req.query("before"));
  const conditions = [eq(activities.userId, c.var.userId)];
  if (Number.isFinite(before) && before > 0) conditions.push(lt(activities.startAt, new Date(before)));
  const rows = await c.var.db
    .select()
    .from(activities)
    .where(and(...conditions))
    .orderBy(desc(activities.startAt))
    .limit(limit);
  const ascentList = await ascentsForActivities(
    c.var.db,
    rows.map((r) => r.id),
  );
  return c.json({
    activities: rows.map((r) => ({ ...toActivity(r), ascents: ascentList.filter((a) => a.activityId === r.id) })),
    nextBefore: rows.length === limit ? rows[rows.length - 1]!.startAt.getTime() : null,
  });
});

/** Detalle con la ruta. A los demás se les recortan las zonas de privacidad del autor. */
activitiesRoutes.get("/:id", async (c) => {
  const db = c.var.db;
  const activity = await db.select().from(activities).where(eq(activities.id, c.req.param("id"))).get();
  if (!activity) return c.json({ error: "not_found" }, 404);
  const relationship = await getRelationship(db, c.var.userId, activity.userId);
  if (!canView(activity.visibility, relationship)) return c.json({ error: "not_found" }, 404);

  const stored = await db.select().from(activityTracks).where(eq(activityTracks.activityId, activity.id)).get();
  const points = stored ? await decodeTrack(stored.data) : [];
  let segments = points.length ? [points] : [];
  if (mustTrimTrack(relationship) && points.length) {
    const zones = await db
      .select({ lat: privacyZones.lat, lon: privacyZones.lon, radiusM: privacyZones.radiusM })
      .from(privacyZones)
      .where(eq(privacyZones.userId, activity.userId));
    segments = applyPrivacyZones(points, zones);
  }

  const visibleAscents = (await ascentsForActivities(db, [activity.id])).filter((a) =>
    canView(a.visibility, relationship),
  );
  return c.json({
    activity: toActivity(activity, { includeBox: relationship === "self" }),
    ascents: visibleAscents,
    track: serializeSegments(segments),
  });
});

/** Cambiar título o visibilidad. La visibilidad se aplica también a sus ascensiones. */
activitiesRoutes.patch("/:id", async (c) => {
  const body = await c.req.json<Record<string, unknown>>().catch(() => null);
  if (!body || typeof body !== "object") return c.json({ error: "invalid_body" }, 400);
  const db = c.var.db;
  const where = and(eq(activities.id, c.req.param("id")), eq(activities.userId, c.var.userId));
  const activity = await db.select().from(activities).where(where).get();
  if (!activity) return c.json({ error: "not_found" }, 404);

  const update: Partial<typeof activities.$inferInsert> = {};
  if (body.title !== undefined) {
    if (body.title !== null && (typeof body.title !== "string" || body.title.length > 120))
      return c.json({ error: "invalid_title" }, 400);
    update.title = typeof body.title === "string" ? body.title.trim() || null : null;
  }
  if (body.visibility !== undefined) {
    if (!isVisibility(body.visibility)) return c.json({ error: "invalid_visibility" }, 400);
    update.visibility = body.visibility;
    await db.update(ascents).set({ visibility: body.visibility }).where(eq(ascents.activityId, activity.id));
  }
  if (Object.keys(update).length) await db.update(activities).set(update).where(where);
  const updated = await db.select().from(activities).where(where).get();
  return c.json({ activity: toActivity(updated!), ascents: await ascentsForActivities(db, [activity.id]) });
});

/** Borra la actividad, su ruta y las ascensiones que salían de ella. */
activitiesRoutes.delete("/:id", async (c) => {
  const db = c.var.db;
  const where = and(eq(activities.id, c.req.param("id")), eq(activities.userId, c.var.userId));
  const activity = await db.select({ id: activities.id }).from(activities).where(where).get();
  if (!activity) return c.json({ error: "not_found" }, 404);
  await db.delete(ascents).where(eq(ascents.activityId, activity.id));
  await db.delete(activities).where(where);
  return c.body(null, 204);
});
