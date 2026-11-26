#!/usr/bin/env node
// Siembra (o actualiza) los retos oficiales de lista de cimas desde la tabla de picos.
// Los retos de meta los siembra la migración 0003; este script solo hace falta tras importar picos.
//
//   cd backend && TURSO_DATABASE_URL=… TURSO_AUTH_TOKEN=… node scripts/seed-challenges.mjs [--dry-run]
//
// Cada lista sale de una caja y una altitud mínima. Para no llenarla de antecimas, se recorren
// los picos de más alto a más bajo y se descarta el que tenga otro ya elegido a menos de `spacingM`.
import { createClient } from "@libsql/client";

export const PEAK_LISTS = [
  // Leyendas: completarlas da su emblema (badgeId), aunque no te hayas unido
  {
    slug: "legend-king-pyrenees",
    badgeId: "king-pyrenees",
    title: "Rey del Pirineo",
    description: "Todos los tresmiles del Pirineo, como la lista clásica: del Aneto a la última aguja.",
    box: [42.0, -2.0, 43.4, 3.4],
    minEle: 3000,
    spacingM: 100,
  },
  {
    slug: "legend-iberian-slam",
    badgeId: "iberian-slam",
    title: "Gran Slam Ibérico",
    description: "El techo de cada gran cordillera: Aneto, Mulhacén, Torre Cerredo, Almanzor, Moncayo y Teide.",
    // El más alto de cada caja
    tops: [
      [42.6, 0.62, 42.66, 0.7],
      [37.03, -3.34, 37.08, -3.28],
      [43.18, -4.88, 43.22, -4.83],
      [40.23, -5.31, 40.26, -5.28],
      [41.76, -1.86, 41.81, -1.8],
      [28.25, -16.66, 28.29, -16.62],
    ],
  },
  {
    slug: "maladeta-3000",
    title: "Tresmiles de la Maladeta",
    description: "Las cimas de más de 3.000 m del macizo de la Maladeta y el Aneto.",
    box: [42.6, 0.58, 42.68, 0.72],
    minEle: 3000,
    spacingM: 600,
  },
  {
    slug: "sierra-nevada-3000",
    title: "Techos de Sierra Nevada",
    description: "Mulhacén, Veleta, Alcazaba y el resto de tresmiles de Sierra Nevada.",
    box: [36.95, -3.5, 37.15, -3.15],
    minEle: 3000,
    spacingM: 900,
  },
  {
    slug: "picos-de-europa-2500",
    title: "Grandes de Picos de Europa",
    description: "Las cimas de más de 2.500 m de los tres macizos de Picos de Europa.",
    box: [43.1, -5.1, 43.3, -4.6],
    minEle: 2500,
    spacingM: 500,
  },
  {
    slug: "gredos-circo",
    title: "Gredos: Almanzor y su circo",
    description: "El Almanzor y las cimas de más de 2.400 m que rodean el circo de Gredos.",
    box: [40.22, -5.33, 40.3, -5.2],
    minEle: 2400,
    spacingM: 500,
  },
  {
    slug: "alps-4000",
    badgeId: "lord-alps",
    title: "Cuatromiles de los Alpes",
    description: "Las cimas de más de 4.000 m de los Alpes, del Mont Blanc al Bernina.",
    box: [43.5, 5, 48.5, 16],
    minEle: 4000,
    spacingM: 500,
  },
];

function distanceM(a, b) {
  const r = Math.PI / 180;
  const dLat = (b.lat - a.lat) * r;
  const dLon = (b.lon - a.lon) * r;
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(a.lat * r) * Math.cos(b.lat * r) * Math.sin(dLon / 2) ** 2;
  return 2 * 6_371_000 * Math.asin(Math.sqrt(h));
}

/** Elige las cimas principales: de más alta a más baja, sin antecimas a menos de `spacingM`. */
export function pickPeaks(rows, spacingM) {
  const kept = [];
  for (const p of [...rows].sort((a, b) => b.ele - a.ele)) {
    if (kept.every((k) => distanceM(k, p) >= spacingM)) kept.push(p);
  }
  return kept;
}

async function main() {
  const dryRun = process.argv.includes("--dry-run");
  const db = createClient({ url: process.env.TURSO_DATABASE_URL, authToken: process.env.TURSO_AUTH_TOKEN });
  for (const [i, list] of PEAK_LISTS.entries()) {
    const toPeak = (r) => ({ id: Number(r.id), name: String(r.name), ele: Number(r.ele), lat: Number(r.lat), lon: Number(r.lon) });
    let peaks;
    let rows = [];
    if (list.tops) {
      peaks = [];
      for (const [south, west, north, east] of list.tops) {
        const top = await db.execute({
          sql: "SELECT id, name, ele, lat, lon FROM peaks WHERE lat BETWEEN ? AND ? AND lon BETWEEN ? AND ? AND ele IS NOT NULL ORDER BY ele DESC LIMIT 1",
          args: [south, north, west, east],
        });
        if (!top.rows[0]) throw new Error(`${list.title}: no hay picos en ${[south, west, north, east]} (¿falta importar la región?)`);
        peaks.push(toPeak(top.rows[0]));
      }
    } else {
      const [south, west, north, east] = list.box;
      ({ rows } = await db.execute({
        sql: "SELECT id, name, ele, lat, lon FROM peaks WHERE lat BETWEEN ? AND ? AND lon BETWEEN ? AND ? AND ele >= ? AND name <> '' AND lower(name) NOT LIKE 'antecima%'",
        args: [south, north, west, east, list.minEle],
      }));
      peaks = pickPeaks(rows.map(toPeak), list.spacingM);
    }
    console.log(`${list.title}: ${peaks.length} cimas (${rows.length} en la caja)`);
    console.log("  " + peaks.map((p) => `${p.name} ${Math.round(p.ele)}`).join(", "));
    if (dryRun) continue;
    const id = `official-${list.slug}`;
    await db.batch(
      [
        {
          sql: `INSERT INTO challenges (id, slug, title, description, visibility, kind, recurrence, sort_order, badge_id)
                VALUES (?, ?, ?, ?, 'public', 'peaks', 'none', ?, ?)
                ON CONFLICT(id) DO UPDATE SET title = excluded.title, description = excluded.description,
                  sort_order = excluded.sort_order, badge_id = excluded.badge_id`,
          args: [id, list.slug, list.title, list.description, 100 + i, list.badgeId ?? null],
        },
        { sql: "DELETE FROM challenge_peaks WHERE challenge_id = ?", args: [id] },
        ...peaks.map((p) => ({ sql: "INSERT INTO challenge_peaks (challenge_id, peak_id) VALUES (?, ?)", args: [id, p.id] })),
      ],
      "write",
    );
  }
}

if (import.meta.url === `file://${process.argv[1]}`) await main();
