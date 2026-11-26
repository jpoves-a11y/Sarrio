import { and, eq, ne } from "drizzle-orm";
import { Hono } from "hono";
import type { AppBindings } from "../env";
import { requireAuth } from "../auth/session";
import { devices, users } from "../db/schema";
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

  if (Object.keys(update).length > 0) {
    await c.var.db.update(users).set(update).where(eq(users.id, c.var.userId));
  }
  const user = await c.var.db.select().from(users).where(eq(users.id, c.var.userId)).get();
  if (!user) return c.json({ error: "not_found" }, 404);
  return c.json(toMe(user));
});

/** Borrado de cuenta (obligatorio en la App Store). Las tablas dependientes caen en cascada. */
meRoutes.delete("/", async (c) => {
  await c.var.db.delete(users).where(eq(users.id, c.var.userId));
  // Las rutas viven en la base de datos y se borran con el usuario (ON DELETE CASCADE).
  return c.body(null, 204);
});
