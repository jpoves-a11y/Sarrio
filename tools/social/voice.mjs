#!/usr/bin/env node
// Narración con Google Cloud Text-to-Speech (voces Chirp 3: HD, español de España).
//
//   node tools/social/voice.mjs voces                              Lista las voces es-ES de Chirp 3: HD
//   node tools/social/voice.mjs decir guion.txt salida.mp3 [voz]   Genera la narración de un guion
//
// La clave va en GOOGLE_TTS_API_KEY; en las sesiones en la nube la pone el proxy (secreto del entorno),
// y Node solo pasa por el proxy con NODE_USE_ENV_PROXY=1 delante del comando.
//
// Formato del guion: una frase por línea, que se genera por separado para darle su propio ritmo.
//   # nota de montaje (no se lee)
//   @1.08 +0.3 Te reto [pause short] a que me digas…
// «@1.08» es la velocidad de esa frase (1 = normal) y «+0.3» los segundos de silencio después.
// Dentro del texto valen las pausas de Chirp 3: HD: [pause short], [pause] y [pause long].
// Cualquier otra cosa entre [corchetes] es una nota y no se lee.

import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const API = "https://texttospeech.googleapis.com/v1";
export const DEFAULT_VOICE = "es-ES-Chirp3-HD-Charon";
const PAUSE = /^\[pause(?: short| long)?\]$/;

/** Las frases del guion con su velocidad y su silencio posterior. */
export function parseScript(script) {
  const lines = [];
  for (const raw of script.split(/\r?\n/)) {
    const line = raw.trim();
    if (!line || line.startsWith("#")) continue;
    const m = /^(?:@([\d.]+)\s+)?(?:\+([\d.]+)\s+)?(.*)$/.exec(line);
    const markup = m[3].replace(/\[[^\]]*\]/g, (tag) => (PAUSE.test(tag) ? tag : "")).replace(/\s{2,}/g, " ").trim();
    if (!markup) continue;
    lines.push({ rate: m[1] ? Number(m[1]) : 1, after: m[2] ? Number(m[2]) : 0.25, markup });
  }
  return lines;
}

/** El texto que se lee, sin marcas (para subtítulos). */
export function narration(script) {
  return parseScript(script)
    .map((l) => l.markup.replace(/\[pause[^\]]*\]\s*/g, "").trim())
    .join("\n");
}

// Sin GOOGLE_TTS_API_KEY no se manda cabecera: en las sesiones en la nube la añade el proxy
// (si mandáramos una de relleno, llegaría esa y Google la rechazaría).
function headers(env) {
  return { "Content-Type": "application/json", ...(env.GOOGLE_TTS_API_KEY ? { "X-Goog-Api-Key": env.GOOGLE_TTS_API_KEY } : {}) };
}

export async function listVoices({ env = process.env, fetchImpl = fetch } = {}) {
  const res = await fetchImpl(`${API}/voices?languageCode=es-ES`, { headers: headers(env) });
  const data = await res.json();
  if (!res.ok) throw new Error(`Google TTS: ${res.status} ${data.error?.message ?? ""}`);
  return (data.voices ?? []).filter((v) => v.name.includes("Chirp3-HD")).map((v) => ({ name: v.name, gender: v.ssmlGender }));
}

/** Una frase a WAV (LINEAR16, 24 kHz). `markup` admite las pausas de Chirp 3: HD. */
export async function synthesize(markup, { voice = DEFAULT_VOICE, rate = 1.0, env = process.env, fetchImpl = fetch } = {}) {
  const res = await fetchImpl(`${API}/text:synthesize`, {
    method: "POST",
    headers: headers(env),
    body: JSON.stringify({
      input: { markup },
      voice: { languageCode: "es-ES", name: voice },
      audioConfig: { audioEncoding: "LINEAR16", speakingRate: rate, sampleRateHertz: 24000 },
    }),
  });
  const data = await res.json();
  if (!res.ok) throw new Error(`Google TTS: ${res.status} ${data.error?.message ?? ""}`);
  return Buffer.from(data.audioContent, "base64");
}

/** Genera cada frase y las une con sus silencios. Devuelve los tiempos de cada frase (para subtítulos). */
export async function speak(script, outFile, { voice = DEFAULT_VOICE, ...opts } = {}) {
  const lines = parseScript(script);
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "sarrio-voz-"));
  const parts = [];
  const timings = [];
  let t = 0;
  for (const [i, l] of lines.entries()) {
    const wav = path.join(tmp, `${i}.wav`);
    fs.writeFileSync(wav, await synthesize(l.markup, { voice, rate: l.rate, ...opts }));
    const dur = Number(execFileSync("ffprobe", ["-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", wav]).toString());
    timings.push({ start: t, end: t + dur, text: l.markup.replace(/\[pause[^\]]*\]\s*/g, "").trim() });
    t += dur + l.after;
    parts.push(wav);
    if (l.after > 0) {
      const sil = path.join(tmp, `${i}-s.wav`);
      execFileSync("ffmpeg", ["-v", "error", "-y", "-f", "lavfi", "-i", "anullsrc=r=24000:cl=mono", "-t", String(l.after), "-c:a", "pcm_s16le", sil]);
      parts.push(sil);
    }
  }
  const list = path.join(tmp, "list.txt");
  fs.writeFileSync(list, parts.map((p) => `file '${p}'`).join("\n"));
  execFileSync("ffmpeg", ["-v", "error", "-y", "-f", "concat", "-safe", "0", "-i", list, "-ar", "44100", "-b:a", "192k", outFile]);
  fs.rmSync(tmp, { recursive: true, force: true });
  return timings;
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  const [cmd, a, b, voice] = process.argv.slice(2);
  if (cmd === "voces") {
    for (const v of await listVoices()) console.log(`${v.name}  ${v.gender}`);
  } else if (cmd === "decir" && a && b) {
    const timings = await speak(fs.readFileSync(a, "utf8"), b, { voice: voice || DEFAULT_VOICE });
    fs.writeFileSync(b.replace(/\.\w+$/, ".json"), JSON.stringify(timings, null, 2));
    console.log(`${b} (${timings.at(-1).end.toFixed(1)} s)`);
  } else {
    console.log("Uso: voice.mjs voces | decir <guion.txt> <salida.mp3> [voz]");
    process.exit(1);
  }
}
