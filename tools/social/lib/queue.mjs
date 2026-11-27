// Cola de publicaciones: marketing/queue/<fecha>/<pieza>.md
//
// Cada pieza es un .md con frontmatter sencillo (clave: valor, listas en [a, b]) y el texto final.
// La línea «Funciones mencionadas: …» es para quien aprueba: se valida que exista y no se publica.

import fs from "node:fs";
import path from "node:path";

export const NETWORKS = {
  bluesky: { maxChars: 300, maxImages: 4, media: "optional" },
  "instagram-imagen": { maxChars: 2200, maxImages: 1, media: "image" },
  "instagram-carrusel": { maxChars: 2200, maxImages: 10, minImages: 2, media: "image" },
  "instagram-reel": { maxChars: 2200, maxImages: 0, media: "video" },
  // Sin publicación automática todavía: se validan y se publican a mano.
  tiktok: { maxChars: 2200, maxImages: 0, media: "video", manual: true },
  "youtube-short": { maxChars: 5000, maxImages: 0, media: "video", manual: true },
  threads: { maxChars: 500, maxImages: 1, media: "optional", manual: true },
};

const FEATURES_LINE = /^funciones mencionadas:\s*(.*)$/im;
const IMAGE_EXT = /\.(jpe?g|png)$/i;
const VIDEO_EXT = /\.(mp4|mov)$/i;

/** Lee el frontmatter (--- … ---) y el cuerpo. Sin dependencias: solo el YAML que usamos. */
export function parsePost(source) {
  const m = /^---\r?\n([\s\S]*?)\r?\n---\r?\n?([\s\S]*)$/.exec(source);
  if (!m) throw new Error("falta el frontmatter (--- … ---)");
  const meta = {};
  for (const raw of m[1].split(/\r?\n/)) {
    const line = raw.replace(/\s+#.*$/, "").trim();
    if (!line) continue;
    const kv = /^([\w-]+):\s*(.*)$/.exec(line);
    if (!kv) throw new Error(`línea de frontmatter no válida: «${raw}»`);
    let value = kv[2].trim();
    if (value.startsWith("[") && value.endsWith("]")) {
      value = value.slice(1, -1).split(",").map((s) => unquote(s.trim())).filter(Boolean);
    } else {
      value = unquote(value);
    }
    meta[kv[1]] = value;
  }
  const body = m[2];
  const features = FEATURES_LINE.exec(body)?.[1]?.trim() ?? null;
  const text = body.replace(FEATURES_LINE, "").trim();
  return { meta, text, features };
}

function unquote(s) {
  return s.replace(/^(["'])(.*)\1$/, "$2");
}

/** Número de grafemas (lo que cuentan Bluesky e Instagram), no de bytes ni de unidades UTF-16. */
export function graphemes(text) {
  return [...new Intl.Segmenter("es", { granularity: "grapheme" }).segment(text)].length;
}

/** Comprueba una pieza ya leída. Devuelve una lista de errores (vacía si está bien). */
export function validatePost(post, { dir } = {}) {
  const errors = [];
  const { meta, text, features } = post;
  const net = NETWORKS[meta.red];
  if (!net) errors.push(`red desconocida «${meta.red ?? ""}» (válidas: ${Object.keys(NETWORKS).join(", ")})`);
  const when = new Date(meta.fecha ?? "");
  if (!meta.fecha || Number.isNaN(when.getTime())) errors.push("fecha no válida (usa ISO 8601 con zona: 2026-12-01T19:30:00+01:00)");
  else if (!/([+-]\d\d:\d\d|Z)$/.test(meta.fecha)) errors.push("la fecha tiene que llevar zona horaria (+01:00)");
  if (!text) errors.push("el texto está vacío");
  if (features === null) errors.push("falta la línea «Funciones mencionadas:» (ver .claude/skills/sarrio-social)");
  const media = [].concat(meta.recursos ?? []);
  if (net) {
    const n = graphemes(text);
    if (n > net.maxChars) errors.push(`el texto tiene ${n} caracteres y ${meta.red} admite ${net.maxChars}`);
    const images = media.filter((f) => IMAGE_EXT.test(f));
    const videos = media.filter((f) => VIDEO_EXT.test(f));
    if (media.length !== images.length + videos.length) errors.push("recursos: solo .jpg, .png, .mp4 o .mov");
    if (images.length > net.maxImages) errors.push(`${meta.red} admite como mucho ${net.maxImages} imágenes`);
    if (net.minImages && images.length < net.minImages) errors.push(`${meta.red} necesita al menos ${net.minImages} imágenes`);
    if (net.media === "image" && images.length === 0) errors.push(`${meta.red} necesita una imagen`);
    if (net.media === "video" && videos.length !== 1) errors.push(`${meta.red} necesita exactamente un vídeo`);
    if (net.media !== "video" && videos.length) errors.push(`${meta.red} no admite vídeo`);
    if (meta.red.startsWith("instagram") && images.some((f) => !/\.jpe?g$/i.test(f)))
      errors.push("Instagram solo acepta imágenes JPEG");
  }
  if (meta.portada) {
    if (meta.red !== "instagram-reel") errors.push("portada solo vale para instagram-reel");
    if (!/\.jpe?g$/i.test(meta.portada)) errors.push("la portada tiene que ser JPEG");
    media.push(meta.portada);
  }
  if (dir) for (const f of media) if (!fs.existsSync(path.join(dir, f))) errors.push(`no existe el recurso ${f}`);
  return errors;
}

/** Todas las piezas de la cola, en orden de fecha. */
export function loadQueue(queueDir) {
  if (!fs.existsSync(queueDir)) return [];
  const posts = [];
  for (const day of fs.readdirSync(queueDir).sort()) {
    const dir = path.join(queueDir, day);
    if (!fs.statSync(dir).isDirectory()) continue;
    for (const file of fs.readdirSync(dir).sort()) {
      if (!file.endsWith(".md")) continue;
      const id = `${day}/${file}`;
      try {
        const post = parsePost(fs.readFileSync(path.join(dir, file), "utf8"));
        posts.push({ id, dir, ...post, errors: validatePost(post, { dir }) });
      } catch (e) {
        posts.push({ id, dir, meta: {}, text: "", features: null, errors: [e.message] });
      }
    }
  }
  return posts.sort((a, b) => String(a.meta.fecha).localeCompare(String(b.meta.fecha)));
}

/** Las que tocan ya: válidas, con fecha pasada y sin publicar. */
export function duePosts(posts, log, now = new Date()) {
  return posts.filter((p) => p.errors.length === 0 && !NETWORKS[p.meta.red].manual && !log[p.id] && new Date(p.meta.fecha) <= now);
}
