import { Hono } from "hono";
import { desc, eq, like, or } from "drizzle-orm";
import type { AppBindings } from "../env";
import { peakMeta, peaks } from "../db/schema";
import { isValidGeohash } from "../lib/geo";

export const peaksRoutes = new Hono<AppBindings>();

/**
 * Versión del conjunto de picos. La app lleva una copia dentro; si esta es más nueva, pide al
 * servidor los paquetes de las zonas que use (y los guarda) en lugar de fiarse de su copia.
 */
peaksRoutes.get("/version", async (c) => {
  const row = await c.var.db.select().from(peakMeta).where(eq(peakMeta.key, "dataset_version")).get();
  c.header("Cache-Control", "public, max-age=3600");
  return c.json({ version: row ? Number(row.value) : null });
});

/**
 * Paquete de picos de una celda geohash de 4 caracteres (~39 × 19 km).
 * La app lo cachea en el dispositivo y detecta las cumbres en local.
 * Los datos de picos son públicos (OSM), así que no requiere sesión y se cachea en el edge.
 */
peaksRoutes.get("/pack/:cell", async (c) => {
  const cell = c.req.param("cell").toLowerCase();
  if (cell.length !== 4 || !isValidGeohash(cell)) {
    return c.json({ error: "cell must be a 4-character geohash" }, 400);
  }
  const rows = await c.var.db
    .select({ id: peaks.id, name: peaks.name, nameEs: peaks.nameEs, ele: peaks.ele, lat: peaks.lat, lon: peaks.lon, range: peaks.range })
    .from(peaks)
    .where(like(peaks.geohash, `${cell}%`));
  c.header("Cache-Control", "public, max-age=86400");
  return c.json({ cell, attribution: "© OpenStreetMap contributors (ODbL)", peaks: rows });
});

/**
 * Búsqueda por nombre (para los picos que no van dentro de la app: la app busca primero en su copia).
 * `?q=` (al menos 2 letras) y `?limit=` (1-30). Los más altos primero.
 */
peaksRoutes.get("/search", async (c) => {
  const q = (c.req.query("q") ?? "").trim();
  if (q.length < 2 || q.length > 60) return c.json({ error: "invalid_query" }, 400);
  const limit = Math.min(Math.max(Number(c.req.query("limit")) || 20, 1), 30);
  const pattern = `%${q.replace(/[%_\\]/g, "")}%`;
  const rows = await c.var.db
    .select({ id: peaks.id, name: peaks.name, nameEs: peaks.nameEs, ele: peaks.ele, lat: peaks.lat, lon: peaks.lon, range: peaks.range })
    .from(peaks)
    .where(or(like(peaks.name, pattern), like(peaks.nameEs, pattern)))
    .orderBy(desc(peaks.ele))
    .limit(limit);
  c.header("Cache-Control", "public, max-age=86400");
  return c.json({ peaks: rows });
});
