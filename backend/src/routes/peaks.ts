import { Hono } from "hono";
import { like } from "drizzle-orm";
import type { AppBindings } from "../env";
import { getDb } from "../db/client";
import { peaks } from "../db/schema";
import { isValidGeohash } from "../lib/geo";

export const peaksRoutes = new Hono<AppBindings>();

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
  const db = getDb(c.env);
  const rows = await db
    .select({ id: peaks.id, name: peaks.name, nameEs: peaks.nameEs, ele: peaks.ele, lat: peaks.lat, lon: peaks.lon })
    .from(peaks)
    .where(like(peaks.geohash, `${cell}%`));
  c.header("Cache-Control", "public, max-age=86400");
  return c.json({ cell, attribution: "© OpenStreetMap contributors (ODbL)", peaks: rows });
});
