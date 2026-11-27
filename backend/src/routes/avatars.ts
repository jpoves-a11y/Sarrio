import { eq } from "drizzle-orm";
import { Hono } from "hono";
import type { AppBindings } from "../env";
import { avatars, users } from "../db/schema";

/**
 * Fotos de perfil públicas: `/avatars/<usuario>/<clave>.jpg`. La clave es la versión de la foto, así
 * que la respuesta no cambia nunca y se guarda en el borde de Cloudflare y en el iPhone un año.
 */
export const avatarsRoutes = new Hono<AppBindings>();

avatarsRoutes.get("/:userId/:file", async (c) => {
  const key = c.req.param("file").replace(/\.jpg$/, "");
  const db = c.var.db;
  const user = await db.select({ key: users.avatarKey }).from(users).where(eq(users.id, c.req.param("userId"))).get();
  if (!user?.key || user.key !== key) return c.json({ error: "not_found" }, 404);
  const row = await db.select({ data: avatars.data }).from(avatars).where(eq(avatars.userId, c.req.param("userId"))).get();
  if (!row) return c.json({ error: "not_found" }, 404);
  return c.body(new Uint8Array(row.data), 200, {
    "Content-Type": "image/jpeg",
    "Cache-Control": "public, max-age=31536000, immutable",
  });
});
