#!/usr/bin/env node
// Cola de publicaciones de Sarrio.
//
//   node tools/social/publish.mjs validate          Comprueba todas las piezas (CI de los PR)
//   node tools/social/publish.mjs publish --dry-run Lista lo que se publicaría ahora
//   node tools/social/publish.mjs publish           Publica lo que toca y lo apunta en el registro
//
// Solo se publica desde main: lo que está en main ya está aprobado (merge del PR).
// Una pieza que lleva más de MAX_LATE_DAYS sin publicarse no sale sola: hay que cambiarle la fecha.

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { loadQueue, duePosts } from "./lib/queue.mjs";
import { publishBluesky } from "./lib/bluesky.mjs";
import { publishInstagram } from "./lib/instagram.mjs";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const QUEUE = path.join(ROOT, "marketing/queue");
const LOG = path.join(ROOT, "marketing/published/log.json");
const MAX_LATE_DAYS = 3;

// Secreto que indica que una red está configurada; sin él, sus piezas esperan sin dar error.
const CONFIGURED_BY = { bluesky: "BLUESKY_HANDLE", instagram: "IG_USER_ID" };

export const PUBLISHERS = {
  bluesky: publishBluesky,
  "instagram-imagen": publishInstagram,
  "instagram-carrusel": publishInstagram,
  "instagram-reel": publishInstagram,
};

const readLog = () => (fs.existsSync(LOG) ? JSON.parse(fs.readFileSync(LOG, "utf8")) : {});
const writeLog = (log) => fs.writeFileSync(LOG, JSON.stringify(log, null, 2) + "\n");

function validate() {
  const posts = loadQueue(QUEUE);
  let bad = 0;
  for (const p of posts) {
    if (p.errors.length) {
      bad++;
      console.log(`❌ ${p.id}`);
      for (const e of p.errors) console.log(`   · ${e}`);
    } else {
      console.log(`✅ ${p.id}  ${p.meta.red}  ${p.meta.fecha}`);
    }
  }
  console.log(`\n${posts.length} piezas, ${bad} con errores.`);
  return bad === 0;
}

async function publish({ dryRun }) {
  const log = readLog();
  const now = new Date();
  const due = duePosts(loadQueue(QUEUE), log, now);
  let failed = 0;
  for (const p of due) {
    const lateDays = (now - new Date(p.meta.fecha)) / 86_400_000;
    if (lateDays > MAX_LATE_DAYS) {
      console.log(`⏭️  ${p.id}: lleva ${Math.floor(lateDays)} días de retraso; cámbiale la fecha para publicarla`);
      continue;
    }
    const key = CONFIGURED_BY[p.meta.red.split("-")[0]];
    if (key && !process.env[key]) {
      console.log(`⏸️  ${p.id}: ${p.meta.red} aún no está configurada (falta el secreto ${key})`);
      continue;
    }
    if (dryRun) {
      console.log(`🟡 ${p.id} → ${p.meta.red} (simulación)`);
      continue;
    }
    try {
      const result = await PUBLISHERS[p.meta.red](p);
      log[p.id] = { red: p.meta.red, publishedAt: new Date().toISOString(), ...result };
      writeLog(log);
      console.log(`✅ ${p.id} → ${result.url ?? result.id}`);
    } catch (e) {
      failed++;
      console.log(`❌ ${p.id}: ${e.message}`);
    }
  }
  if (!due.length) console.log("Nada que publicar ahora.");
  return failed === 0;
}

const [cmd, ...flags] = process.argv.slice(2);
if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  let ok;
  if (cmd === "validate") ok = validate();
  else if (cmd === "publish") ok = await publish({ dryRun: flags.includes("--dry-run") });
  else {
    console.log("Uso: publish.mjs validate | publish [--dry-run]");
    ok = false;
  }
  process.exit(ok ? 0 : 1);
}
