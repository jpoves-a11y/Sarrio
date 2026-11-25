import { eq } from "drizzle-orm";
import { Hono } from "hono";
import type { AppBindings } from "../env";
import { requireAuth } from "../auth/session";
import { users } from "../db/schema";
import { normalizeUsername } from "../lib/validation";
import { toPublicUser } from "../services/users";

export const usersRoutes = new Hono<AppBindings>();
usersRoutes.use("*", requireAuth);

/** Perfil público por username. Fase 6 añadirá relación de amistad, bloqueos y estadísticas. */
usersRoutes.get("/:username", async (c) => {
  const user = await c.var.db
    .select()
    .from(users)
    .where(eq(users.username, normalizeUsername(c.req.param("username"))))
    .get();
  if (!user) return c.json({ error: "not_found" }, 404);
  return c.json(toPublicUser(user));
});
