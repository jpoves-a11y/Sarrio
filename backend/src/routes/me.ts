import { and, eq, ne } from "drizzle-orm";
import { Hono } from "hono";
import type { AppBindings } from "../env";
import { requireAuth } from "../auth/session";
import { avatars, devices, privacyZones, users } from "../db/schema";
import { newId } from "../lib/ids";
import { badgeCount } from "../services/badgeCount";
import { sendToUser } from "../services/push";
import { isValidUsername, isVisibility, normalizeUsername } from "../lib/validation";
import { toMe } from "../services/users";

export const meRoutes = new Hono<AppBindings>();
meRoutes.use("*", requireAuth);

meRoutes.get("/", async (c) => {
  const user = await c.var.db.select().from(users).where(eq(users.id, c.var.userId)).get();
  if (!user) return c.json({ error: "not_found" }, 404);
  return c.json(toMe(user));
});

/** Novedades para el número del icono y de la pestaña Amigos. */
meRoutes.get("/badge", async (c) => c.json(await badgeCount(c.var.db, c.var.userId)));

/** Token de notificaciones push del iPhone (uno por dispositivo; si cambia de usuario, pasa al nuevo). */
meRoutes.post("/devices", async (c) => {
  const body = await c.req.json<Record<string, unknown>>().catch(() => null);
  const token = typeof body?.token === "string" ? body.token.trim().toLowerCase() : "";
  const environment = body?.environment === "sandbox" ? "sandbox" : "production";
  if (!/^[0-9a-f]{32,200}$/.test(token)) return c.json({ error: "invalid_token" }, 400);
  await c.var.db
    .insert(devices)
    .values({ token, userId: c.var.userId, environment })
    .onConflictDoUpdate({ target: devices.token, set: { userId: c.var.userId, environment } });
  return c.json({ registered: true });
});

/** Prueba de notificaciones: envía un push a mis iPhone y devuelve la respuesta de APNs. */
meRoutes.post("/push-test", async (c) => {
  if (!c.env.APNS_KEY || !c.env.APNS_KEY_ID || !c.env.APNS_TEAM_ID) return c.json({ error: "apns_not_configured" }, 503);
  try {
    const results = await sendToUser(c.env, c.var.db, c.var.deps.fetch ?? fetch, c.var.userId, {
      title: "Sarrio",
      body: "Las notificaciones funcionan ⛰️",
      data: { open: "feed" },
    });
    return c.json({ results });
  } catch (e) {
    return c.json({ error: "push_failed", detail: String(e) }, 502);
  }
});

// ---------------------------------------------------------------------------
// Zonas de privacidad: los demás no ven el tramo de tus rutas dentro de ellas
// ---------------------------------------------------------------------------

const MAX_ZONES = 10;

meRoutes.get("/privacy-zones", async (c) => {
  const zones = await c.var.db.select().from(privacyZones).where(eq(privacyZones.userId, c.var.userId));
  return c.json({ zones: zones.map(({ id, lat, lon, radiusM }) => ({ id, lat, lon, radiusM })) });
});

meRoutes.post("/privacy-zones", async (c) => {
  const body = await c.req.json<Record<string, unknown>>().catch(() => null);
  const lat = Number(body?.lat), lon = Number(body?.lon), radiusM = Math.round(Number(body?.radiusM ?? 500));
  if (!Number.isFinite(lat) || !Number.isFinite(lon) || Math.abs(lat) > 90 || Math.abs(lon) > 180)
    return c.json({ error: "invalid_location" }, 400);
  if (!Number.isFinite(radiusM) || radiusM < 100 || radiusM > 2000) return c.json({ error: "invalid_radius" }, 400);
  const db = c.var.db;
  const existing = await db.select({ id: privacyZones.id }).from(privacyZones).where(eq(privacyZones.userId, c.var.userId));
  if (existing.length >= MAX_ZONES) return c.json({ error: "too_many_zones" }, 400);
  const [zone] = await db.insert(privacyZones).values({ id: newId(), userId: c.var.userId, lat, lon, radiusM }).returning();
  return c.json({ id: zone!.id, lat: zone!.lat, lon: zone!.lon, radiusM: zone!.radiusM }, 201);
});

meRoutes.delete("/privacy-zones/:id", async (c) => {
  await c.var.db
    .delete(privacyZones)
    .where(and(eq(privacyZones.id, c.req.param("id")), eq(privacyZones.userId, c.var.userId)));
  return c.body(null, 204);
});

meRoutes.delete("/devices/:token", async (c) => {
  await c.var.db.delete(devices).where(and(eq(devices.token, c.req.param("token").toLowerCase()), eq(devices.userId, c.var.userId)));
  return c.body(null, 204);
});

meRoutes.patch("/", async (c) => {
  const body = await c.req.json<Record<string, unknown>>().catch(() => null);
  if (!body || typeof body !== "object") return c.json({ error: "invalid_body" }, 400);

  const update: Partial<typeof users.$inferInsert> = {};

  if (body.username !== undefined) {
    if (typeof body.username !== "string") return c.json({ error: "invalid_username" }, 400);
    const username = normalizeUsername(body.username);
    if (!isValidUsername(username)) return c.json({ error: "invalid_username" }, 400);
    const taken = await c.var.db
      .select({ id: users.id })
      .from(users)
      .where(and(eq(users.username, username), ne(users.id, c.var.userId)))
      .get();
    if (taken) return c.json({ error: "username_taken" }, 409);
    update.username = username;
  }
  if (body.displayName !== undefined) {
    if (typeof body.displayName !== "string") return c.json({ error: "invalid_display_name" }, 400);
    const name = body.displayName.trim();
    if (name.length < 1 || name.length > 50) return c.json({ error: "invalid_display_name" }, 400);
    update.displayName = name;
  }
  if (body.bio !== undefined) {
    if (body.bio !== null && typeof body.bio !== "string") return c.json({ error: "invalid_bio" }, 400);
    const bio = typeof body.bio === "string" ? body.bio.trim() : null;
    if (bio && bio.length > 280) return c.json({ error: "invalid_bio" }, 400);
    update.bio = bio || null;
  }
  if (body.defaultVisibility !== undefined) {
    if (!isVisibility(body.defaultVisibility)) return c.json({ error: "invalid_visibility" }, 400);
    update.defaultVisibility = body.defaultVisibility;
  }
  if (body.city !== undefined) {
    if (body.city !== null && typeof body.city !== "string") return c.json({ error: "invalid_city" }, 400);
    const city = typeof body.city === "string" ? body.city.trim() : "";
    if (city.length > 60) return c.json({ error: "invalid_city" }, 400);
    update.city = city || null;
  }

  if (Object.keys(update).length > 0) {
    await c.var.db.update(users).set(update).where(eq(users.id, c.var.userId));
  }
  const user = await c.var.db.select().from(users).where(eq(users.id, c.var.userId)).get();
  if (!user) return c.json({ error: "not_found" }, 404);
  return c.json(toMe(user));
});

// ---------------------------------------------------------------------------
// Foto de perfil: JPEG pequeño (la app la recorta y la deja en 512 px)
// ---------------------------------------------------------------------------

const MAX_AVATAR = 300 * 1024;

meRoutes.put("/avatar", async (c) => {
  const data = new Uint8Array(await c.req.arrayBuffer());
  if (data.length === 0 || data.length > MAX_AVATAR) return c.json({ error: "invalid_avatar_size" }, 400);
  // JPEG: empieza por FF D8 FF
  if (data[0] !== 0xff || data[1] !== 0xd8 || data[2] !== 0xff) return c.json({ error: "invalid_avatar_format" }, 400);
  const db = c.var.db;
  await db
    .insert(avatars)
    .values({ userId: c.var.userId, data: Buffer.from(data) })
    .onConflictDoUpdate({ target: avatars.userId, set: { data: Buffer.from(data), updatedAt: new Date() } });
  // Clave nueva en cada foto: la URL cambia y ningún caché sirve la antigua
  const avatarKey = newId();
  await db.update(users).set({ avatarKey }).where(eq(users.id, c.var.userId));
  return c.json({ avatarKey });
});

meRoutes.delete("/avatar", async (c) => {
  await c.var.db.delete(avatars).where(eq(avatars.userId, c.var.userId));
  await c.var.db.update(users).set({ avatarKey: null }).where(eq(users.id, c.var.userId));
  return c.json({ avatarKey: null });
});

/** Borrado de cuenta (obligatorio en la App Store). Las tablas dependientes caen en cascada. */
meRoutes.delete("/", async (c) => {
  await c.var.db.delete(users).where(eq(users.id, c.var.userId));
  // Las rutas viven en la base de datos y se borran con el usuario (ON DELETE CASCADE).
  return c.body(null, 204);
});
