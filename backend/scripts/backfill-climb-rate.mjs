#!/usr/bin/env node
// Calcula la velocidad de subida (m/h) de las actividades que ya estaban subidas antes de la
// migración 0010. Mismo cálculo que `climbRate` en src/lib/track.ts.
//
//   cd backend && TURSO_DATABASE_URL=… TURSO_AUTH_TOKEN=… node scripts/backfill-climb-rate.mjs
import { createClient } from "@libsql/client";
import { gunzipSync } from "node:zlib";

function climbRate(points) {
  let gain = 0, time = 0, start = null;
  for (const p of points) {
    if (p[2] == null || p[3] == null) continue;
    if (!start) { start = p; continue; }
    const dt = p[3] - start[3];
    if (dt < 60) continue;
    const de = p[2] - start[2];
    if (de > 1 && dt <= 900) { gain += de; time += dt; }
    start = p;
  }
  if (time < 600 || gain <= 0) return null;
  return Math.min(3000, Math.round((gain / time) * 3600));
}

const db = createClient({ url: process.env.TURSO_DATABASE_URL, authToken: process.env.TURSO_AUTH_TOKEN });
const { rows } = await db.execute(
  "SELECT t.activity_id AS id, t.data AS data FROM activity_tracks t JOIN activities a ON a.id = t.activity_id WHERE a.climb_rate_mh IS NULL",
);
let done = 0;
for (const r of rows) {
  const points = JSON.parse(gunzipSync(Buffer.from(r.data)).toString("utf8"));
  const rate = climbRate(points);
  if (rate == null) continue;
  await db.execute({ sql: "UPDATE activities SET climb_rate_mh = ? WHERE id = ?", args: [rate, r.id] });
  done++;
}
console.log(`Velocidad de subida calculada en ${done} de ${rows.length} actividades`);
