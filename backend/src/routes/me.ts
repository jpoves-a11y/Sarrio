import { and, eq, ne } from "drizzle-orm";
import { Hono } from "hono";
import type { AppBindings } from "../env";
import { requireAuth } from "../auth/session";
import { users } from "../db/schema";
import { isValidUsername, isVisibility, normalizeUsername } from "../lib/validation";
import { toMe } from "../services/users";

export const meRoutes = new Hono<AppBindings>();
meRoutes.use("*", requireAuth);

meRoutes.get("/", async (c) => {
  const user = await c.var.db.select().from(users).where(eq(users.id, c.var.userId)).get();
  if (!user) return c.json({ error: "not_found" }, 404);
  return c.json(toMe(user));
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
