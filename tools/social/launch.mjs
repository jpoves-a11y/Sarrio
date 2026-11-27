#!/usr/bin/env node
// Kit de lanzamiento (marketing/launch): piezas con «dia» relativo al lanzamiento en vez de fecha.
//
//   node tools/social/launch.mjs check               Valida el kit (CI)
//   node tools/social/launch.mjs schedule 2027-03-02 Lo pasa a la cola con fechas reales
//
// «schedule» crea marketing/queue/<fecha>-lanzamiento/: cambia {{fecha}} por «2 de marzo», calcula
// cada fecha en hora de Madrid, genera las diapositivas y copia los clips de marketing/clips/inbox.
// Los clips que falten se avisan (y la validación de la cola fallará hasta que estén).

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { parsePost, validatePost } from "./lib/queue.mjs";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const KIT = path.join(ROOT, "marketing/launch");
const QUEUE = path.join(ROOT, "marketing/queue");
const CLIPS = path.join(ROOT, "marketing/clips/inbox");
const TZ = "Europe/Madrid";
const VIDEO = /\.(mp4|mov)$/i;

/** «2 de marzo» */
export function humanDate(isoDay) {
  return new Date(`${isoDay}T12:00:00Z`).toLocaleDateString("es-ES", { day: "numeric", month: "long", timeZone: TZ });
}

export function addDays(isoDay, n) {
  const d = new Date(`${isoDay}T12:00:00Z`);
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}

/** Desfase de Madrid ese día y a esa hora («+01:00» en invierno, «+02:00» en verano). */
export function madridOffset(isoDay, hhmm) {
  // Probamos los dos desfases posibles y nos quedamos con el que, leído en Madrid, da esa hora.
  for (const off of ["+01:00", "+02:00"]) {
    const d = new Date(`${isoDay}T${hhmm}:00${off}`);
    const local = d.toLocaleTimeString("es-ES", { hour: "2-digit", minute: "2-digit", hour12: false, timeZone: TZ });
    if (local === hhmm) return off;
  }
  return "+01:00";
}

export function fill(text, isoDay) {
  return text.replaceAll("{{fecha}}", humanDate(isoDay));
}

function kitPieces() {
  return fs.readdirSync(KIT).filter((f) => f.endsWith(".md")).sort();
}

function slideCounts() {
  const counts = {};
  for (const d of fs.readdirSync(KIT)) {
    const spec = path.join(KIT, d, "slides.json");
    if (fs.existsSync(spec)) {
      const json = JSON.parse(fs.readFileSync(spec, "utf8"));
      counts[json.nombre ?? d] = { dir: d, n: json.slides.length };
    }
  }
  return counts;
}

/** Errores del kit. Las imágenes tienen que salir de algún slides.json; los vídeos son clips que grabar. */
export function checkKit() {
  const errors = [];
  const clips = new Set();
  const counts = slideCounts();
  for (const file of kitPieces()) {
    const src = fs.readFileSync(path.join(KIT, file), "utf8");
    let post;
    try {
      post = parsePost(src);
    } catch (e) {
      errors.push(`${file}: ${e.message}`);
      continue;
    }
    const { meta } = post;
    const fileErrors = [];
    if (!/^-?\d+$/.test(meta.dia ?? "")) fileErrors.push("falta «dia» (entero, relativo al lanzamiento)");
    if (!/^\d\d:\d\d$/.test(meta.hora ?? "")) fileErrors.push("falta «hora» (HH:MM, hora de Madrid)");
    // Validamos como si ya tuviera fecha, con la fecha más larga posible en el texto.
    const sample = parsePost(fill(src, "2027-09-30"));
    sample.meta.fecha = "2027-09-30T19:30:00+02:00";
    fileErrors.push(...validatePost(sample));
    for (const r of [].concat(meta.recursos ?? [])) {
      if (VIDEO.test(r)) clips.add(r);
      else {
        const m = /^(.+)-(\d\d)\.jpg$/.exec(r);
        const c = m && counts[m[1]];
        if (!c || Number(m[2]) < 1 || Number(m[2]) > c.n) fileErrors.push(`${r} no sale de ningún slides.json`);
      }
    }
    errors.push(...fileErrors.map((e) => `${file}: ${e}`));
  }
  return { errors, clips: [...clips].sort() };
}

export async function schedule(launchDay) {
  if (!/^\d{4}-\d\d-\d\d$/.test(launchDay)) throw new Error("la fecha va como 2027-03-02");
  const { errors } = checkKit();
  if (errors.length) throw new Error(`el kit tiene errores:\n${errors.join("\n")}`);
  const out = path.join(QUEUE, `${launchDay}-lanzamiento`);
  if (fs.existsSync(out)) throw new Error(`ya existe ${path.relative(ROOT, out)}`);
  fs.mkdirSync(out, { recursive: true });

  const missing = new Set();
  for (const file of kitPieces()) {
    const src = fill(fs.readFileSync(path.join(KIT, file), "utf8"), launchDay);
    const { meta } = parsePost(src);
    const day = addDays(launchDay, Number(meta.dia));
    const fecha = `${day}T${meta.hora}:00${madridOffset(day, meta.hora)}`;
    const piece = src.replace(/^dia:.*\n/m, `fecha: ${fecha}\n`).replace(/^hora:.*\n/m, "");
    fs.writeFileSync(path.join(out, file), piece);
    for (const r of [].concat(meta.recursos ?? [])) {
      if (!VIDEO.test(r)) continue;
      const clip = path.join(CLIPS, r);
      if (fs.existsSync(clip)) fs.copyFileSync(clip, path.join(out, r));
      else missing.add(r);
    }
  }

  const { render } = await import("./render.mjs");
  for (const { dir } of Object.values(slideCounts())) {
    const tmp = path.join(out, dir);
    fs.mkdirSync(tmp);
    fs.writeFileSync(path.join(tmp, "slides.json"), fill(fs.readFileSync(path.join(KIT, dir, "slides.json"), "utf8"), launchDay));
    await render(tmp);
  }
  return { out, missing: [...missing].sort() };
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  const [cmd, arg] = process.argv.slice(2);
  if (cmd === "check") {
    const { errors, clips } = checkKit();
    for (const e of errors) console.log(`❌ ${e}`);
    console.log(`${kitPieces().length} piezas en el kit, ${errors.length} errores. Clips que hacen falta: ${clips.join(", ") || "ninguno"}.`);
    process.exit(errors.length ? 1 : 0);
  } else if (cmd === "schedule") {
    const { out, missing } = await schedule(arg);
    console.log(`Cola creada en ${path.relative(ROOT, out)}.`);
    if (missing.length) console.log(`⚠️  Faltan clips en marketing/clips/inbox: ${missing.join(", ")}`);
  } else {
    console.log("Uso: launch.mjs check | schedule <AAAA-MM-DD>");
    process.exit(1);
  }
}
