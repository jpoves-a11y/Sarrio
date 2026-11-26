#!/usr/bin/env node
// Descarga picos (natural=peak con nombre) de OpenStreetMap vía Overpass y genera SQL para Turso.
// Datos © OpenStreetMap contributors, licencia ODbL: la app debe mostrar la atribución.
//
// Uso:
//   node tools/peaks/fetch-peaks.mjs pirineos > peaks-pirineos.sql
//   node tools/peaks/fetch-peaks.mjs --from-file overpass.json --range Pirineos > peaks.sql
//   turso db shell sarrio < peaks-pirineos.sql
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const OVERPASS_URL = process.env.OVERPASS_URL ?? "https://overpass-api.de/api/interpreter";
const here = path.dirname(fileURLToPath(import.meta.url));

const BASE32 = "0123456789bcdefghjkmnpqrstuvwxyz";
export function geohash(lat, lon, precision = 5) {
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

/** "3.404 m", "3404", "3404,5" → 3404 */
export function parseEle(raw) {
  if (!raw) return null;
  const cleaned = String(raw).replace(/\s*m$/i, "").replace(/\.(?=\d{3}\b)/g, "").replace(",", ".");
  const n = Number.parseFloat(cleaned);
  return Number.isFinite(n) && n > -500 && n < 9000 ? n : null;
}

const q = (v) => (v == null ? "NULL" : typeof v === "number" ? String(v) : `'${String(v).replace(/'/g, "''")}'`);

export function toSql(elements, range) {
  const lines = ["BEGIN;"];
  let count = 0;
  for (const el of elements) {
    if (el.type !== "node" || !el.tags?.name) continue;
    const t = el.tags;
    const values = [
      el.id, t.name, t["name:es"] ?? null, parseEle(t.ele), el.lat, el.lon,
      geohash(el.lat, el.lon, 5), t["is_in:country_code"] ?? null, range ?? null, t.wikidata ?? null,
    ];
    lines.push(
      `INSERT INTO peaks (id, name, name_es, ele, lat, lon, geohash, country, range, wikidata) VALUES (${values.map(q).join(", ")})` +
        ` ON CONFLICT(id) DO UPDATE SET name=excluded.name, name_es=excluded.name_es, ele=excluded.ele, lat=excluded.lat,` +
        ` lon=excluded.lon, geohash=excluded.geohash, range=COALESCE(excluded.range, peaks.range), wikidata=excluded.wikidata;`,
    );
    count++;
  }
  lines.push("COMMIT;");
  return { sql: lines.join("\n") + "\n", count };
}

async function fetchRegion([south, west, north, east]) {
  const query = `[out:json][timeout:180];node["natural"="peak"]["name"](${south},${west},${north},${east});out body;`;
  // Overpass es público y a veces está saturado (429/502/503/504): reintenta con espera exponencial.
  const retryable = new Set([429, 502, 503, 504]);
  for (let attempt = 0, wait = 15; ; attempt++, wait *= 2) {
    const res = await fetch(OVERPASS_URL, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded", "User-Agent": "sarrio-peaks-importer/0.1" },
      body: "data=" + encodeURIComponent(query),
    });
    if (res.ok) return (await res.json()).elements;
    const text = await res.text();
    if (!retryable.has(res.status) || attempt >= 5) throw new Error(`Overpass ${res.status}: ${text}`);
    console.error(`Overpass ${res.status}; reintento en ${wait} s…`);
    await new Promise((r) => setTimeout(r, wait * 1000));
  }
}

async function main() {
  const args = process.argv.slice(2);
  const fromFile = args.includes("--from-file") ? args[args.indexOf("--from-file") + 1] : null;
  let range = args.includes("--range") ? args[args.indexOf("--range") + 1] : undefined;
  let elements;
  if (fromFile) {
    elements = JSON.parse(fs.readFileSync(fromFile, "utf8")).elements;
  } else {
    const regions = JSON.parse(fs.readFileSync(path.join(here, "regions.json"), "utf8"));
    const name = args.find((a) => !a.startsWith("--"));
    const region = regions[name];
    if (!region) {
      console.error(`Región desconocida "${name}". Disponibles: ${Object.keys(regions).join(", ")}`);
      process.exit(1);
    }
    range ??= region.range;
    elements = await fetchRegion(region.bbox);
  }
  const { sql, count } = toSql(elements, range);
  process.stdout.write(sql);
  console.error(`${count} picos exportados.`);
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  main().catch((e) => { console.error(e); process.exit(1); });
}
