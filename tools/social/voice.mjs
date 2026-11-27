#!/usr/bin/env node
// Narración con Google Cloud Text-to-Speech (voces Chirp 3: HD, español de España).
//
//   node tools/social/voice.mjs voces                                  Lista las voces es-ES de Chirp 3: HD
//   node tools/social/voice.mjs decir guion.txt salida.mp3 [voz]       Genera la narración de un guion
//
// La clave va en GOOGLE_TTS_API_KEY (en las sesiones en la nube la pone el proxy).
// Las líneas del guion que empiezan por «#» o están entre [corchetes] son notas de montaje y no se leen.

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const API = "https://texttospeech.googleapis.com/v1";
export const DEFAULT_VOICE = "es-ES-Chirp3-HD-Charon";

/** El texto que se lee: sin notas de montaje ni líneas vacías de más. */
export function narration(script) {
  return script
    .split(/\r?\n/)
    .filter((l) => !l.trim().startsWith("#"))
    .map((l) => l.replace(/\[[^\]]*\]/g, "").trim())
    .filter(Boolean)
    .join("\n");
}

function headers(env) {
  return { "Content-Type": "application/json", "X-Goog-Api-Key": env.GOOGLE_TTS_API_KEY || "proxy" };
}

export async function listVoices({ env = process.env, fetchImpl = fetch } = {}) {
  const res = await fetchImpl(`${API}/voices?languageCode=es-ES`, { headers: headers(env) });
  const data = await res.json();
  if (!res.ok) throw new Error(`Google TTS: ${res.status} ${data.error?.message ?? ""}`);
  return (data.voices ?? []).filter((v) => v.name.includes("Chirp3-HD")).map((v) => ({ name: v.name, gender: v.ssmlGender }));
}

export async function synthesize(text, { voice = DEFAULT_VOICE, rate = 1.0, env = process.env, fetchImpl = fetch } = {}) {
  const res = await fetchImpl(`${API}/text:synthesize`, {
    method: "POST",
    headers: headers(env),
    body: JSON.stringify({
      input: { text },
      voice: { languageCode: "es-ES", name: voice },
      audioConfig: { audioEncoding: "MP3", speakingRate: rate, sampleRateHertz: 44100 },
    }),
  });
  const data = await res.json();
  if (!res.ok) throw new Error(`Google TTS: ${res.status} ${data.error?.message ?? ""}`);
  return Buffer.from(data.audioContent, "base64");
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  const [cmd, a, b, voice] = process.argv.slice(2);
  if (cmd === "voces") {
    for (const v of await listVoices()) console.log(`${v.name}  ${v.gender}`);
  } else if (cmd === "decir" && a && b) {
    const audio = await synthesize(narration(fs.readFileSync(a, "utf8")), { voice: voice || DEFAULT_VOICE });
    fs.writeFileSync(b, audio);
    console.log(`${b} (${audio.length} bytes)`);
  } else {
    console.log("Uso: voice.mjs voces | decir <guion.txt> <salida.mp3> [voz]");
    process.exit(1);
  }
}
