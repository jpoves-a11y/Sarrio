#!/usr/bin/env node
// Genera los picos que viajan dentro de la app (ios/Sarrio/Resources/peaks.tsv) desde la tabla de
// picos de Turso. Lo ejecuta el workflow de TestFlight antes de compilar.
//
//   cd backend && TURSO_DATABASE_URL=… TURSO_AUTH_TOKEN=… node scripts/export-peaks-bundle.mjs ../ios/Sarrio/Resources/peaks.tsv
//
// Formato: ver SarrioKit/PeakBundle.swift. Las celdas «cubiertas» son las de las regiones importadas
// (tools/peaks/regions.json): en ellas la app no necesita preguntar al servidor.
import { createClient } from "@libsql/client";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const regionsFile = path.join(here, "..", "..", "tools", "peaks", "regions.json");
/** Regiones importadas en la base de datos (las que la copia cubre por completo). */
const BUNDLED_REGIONS = [
  "pirineos", "sierra-nevada", "picos-de-europa", "sistema-central", "moncayo", "teide",
  "alpes-so", "alpes-sc", "alpes-se", "alpes-no", "alpes-nc", "alpes-ne",
];

const BASE32 = "0123456789bcdefghjkmnpqrstuvwxyz";
function geohash(lat, lon, precision) {
  let latR = [-90, 90], lonR = [-180, 180], hash = "", bit = 0, ch = 0, even = true;
  while (hash.length < precision) {
    const r = even ? lonR : latR;
    const v = even ? lon : lat;
    const mid = (r[0] + r[1]) / 2;
    if (v >= mid) { ch = (ch << 1) | 1; r[0] = mid; } else { ch <<= 1; r[1] = mid; }
    even = !even;
    if (++bit === 5) { hash += BASE32[ch]; bit = 0; ch = 0; }
  }
  return hash;
}

/** Celdas de 4 caracteres de una caja (muestreo fino, como Geo.geohashCells en Swift). */
function cellsOf([south, west, north, east]) {
  const cells = new Set();
  const step = 0.05;
  for (let lat = south; lat <= north + step; lat += step) {
    for (let lon = west; lon <= east + step; lon += step) {
      cells.add(geohash(Math.min(lat, north), Math.min(lon, east), 4));
    }
  }
  return cells;
}

const clean = (s) => (s == null ? "" : String(s).replace(/[\t\r\n]+/g, " ").trim());

async function main() {
  const out = process.argv[2];
  if (!out) throw new Error("Uso: export-peaks-bundle.mjs <salida.tsv>");
  const { TURSO_DATABASE_URL: url, TURSO_AUTH_TOKEN: authToken } = process.env;
  if (!url) throw new Error("Falta TURSO_DATABASE_URL");

  const regions = JSON.parse(fs.readFileSync(regionsFile, "utf8"));
  const db = createClient({ url, authToken });

  // Solo cuentan como cubiertas las regiones que de verdad tienen picos importados: si una
  // importación falló, la app seguirá preguntando al servidor por esas zonas
  const covered = new Set();
  for (const name of BUNDLED_REGIONS) {
    if (!regions[name]) throw new Error(`Región desconocida: ${name}`);
    const [south, west, north, east] = regions[name].bbox;
    const n = Number((await db.execute({
      sql: "select count(*) as n from peaks where lat between ? and ? and lon between ? and ?",
      args: [south, north, west, east],
    })).rows[0].n);
    if (n === 0) {
      console.warn(`::warning::${name} no tiene picos importados: no se marca como cubierta`);
      continue;
    }
    for (const cell of cellsOf(regions[name].bbox)) covered.add(cell);
  }

  const version = (await db.execute("select value from peak_meta where key = 'dataset_version'")).rows[0]?.value ?? Date.now();
  const rows = (await db.execute("select geohash, id, lat, lon, ele, name, name_es, range from peaks order by geohash, id")).rows;

  const lines = [
    "#sarrio-peaks 1",
    `#version ${version}`,
    `#cells ${[...covered].sort().join(" ")}`,
    "# Datos de picos © OpenStreetMap contributors, ODbL",
  ];
  for (const r of rows) {
    const ele = r.ele == null ? "" : String(Math.round(Number(r.ele)));
    lines.push([r.geohash, r.id, Number(r.lat).toFixed(5), Number(r.lon).toFixed(5), ele, clean(r.name), clean(r.name_es), clean(r.range)].join("\t"));
  }
  fs.mkdirSync(path.dirname(out), { recursive: true });
  fs.writeFileSync(out, lines.join("\n") + "\n");
  const kb = Math.round(fs.statSync(out).size / 1024);
  console.log(`${rows.length} picos y ${covered.size} celdas cubiertas → ${out} (${kb} KB, versión ${version})`);
}

main().catch((e) => {
  console.error(e.message);
  process.exit(1);
});
