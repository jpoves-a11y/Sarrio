// Publicar en Bluesky (AT Protocol). Necesita BLUESKY_HANDLE y BLUESKY_APP_PASSWORD
// (contraseña de aplicación: Ajustes → Privacidad y seguridad → Contraseñas de aplicación).

import fs from "node:fs";
import path from "node:path";

const SERVICE = "https://bsky.social";
const MAX_BLOB = 1_000_000;

/** Hashtags y enlaces como facets (posiciones en bytes UTF-8, como pide el protocolo). */
export function facetsFor(text) {
  const facets = [];
  const enc = new TextEncoder();
  const byteAt = (i) => enc.encode(text.slice(0, i)).length;
  for (const m of text.matchAll(/https?:\/\/[^\s)]+[^\s).,;:!?]/g)) {
    facets.push({
      index: { byteStart: byteAt(m.index), byteEnd: byteAt(m.index + m[0].length) },
      features: [{ $type: "app.bsky.richtext.facet#link", uri: m[0] }],
    });
  }
  for (const m of text.matchAll(/(^|\s)#([\p{L}\p{N}_]+)/gu)) {
    const start = m.index + m[1].length;
    facets.push({
      index: { byteStart: byteAt(start), byteEnd: byteAt(start + 1 + m[2].length) },
      features: [{ $type: "app.bsky.richtext.facet#tag", tag: m[2] }],
    });
  }
  return facets.sort((a, b) => a.index.byteStart - b.index.byteStart);
}

async function xrpc(fetchImpl, method, { token, json, body, contentType } = {}) {
  const res = await fetchImpl(`${SERVICE}/xrpc/${method}`, {
    method: "POST",
    headers: {
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      "Content-Type": json ? "application/json" : contentType,
    },
    body: json ? JSON.stringify(json) : body,
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(`Bluesky ${method}: ${res.status} ${data.error ?? ""} ${data.message ?? ""}`.trim());
  return data;
}

export async function publishBluesky(post, { env = process.env, fetchImpl = fetch } = {}) {
  const { BLUESKY_HANDLE: handle, BLUESKY_APP_PASSWORD: password } = env;
  if (!handle || !password) throw new Error("faltan BLUESKY_HANDLE o BLUESKY_APP_PASSWORD");
  const session = await xrpc(fetchImpl, "com.atproto.server.createSession", { json: { identifier: handle, password } });

  const files = [].concat(post.meta.recursos ?? []);
  const alts = [].concat(post.meta.alt ?? []);
  const images = [];
  for (const [i, file] of files.entries()) {
    const bytes = fs.readFileSync(path.join(post.dir, file));
    if (bytes.length > MAX_BLOB) throw new Error(`${file} pesa ${bytes.length} bytes; Bluesky admite 1 MB`);
    const type = /\.png$/i.test(file) ? "image/png" : "image/jpeg";
    const { blob } = await xrpc(fetchImpl, "com.atproto.repo.uploadBlob", { token: session.accessJwt, body: bytes, contentType: type });
    images.push({ alt: alts[i] ?? alts[0] ?? "", image: blob });
  }

  const record = {
    $type: "app.bsky.feed.post",
    text: post.text,
    langs: ["es"],
    createdAt: new Date().toISOString(),
    facets: facetsFor(post.text),
    ...(images.length ? { embed: { $type: "app.bsky.embed.images", images } } : {}),
  };
  const { uri } = await xrpc(fetchImpl, "com.atproto.repo.createRecord", {
    token: session.accessJwt,
    json: { repo: session.did, collection: "app.bsky.feed.post", record },
  });
  return { id: uri, url: `https://bsky.app/profile/${handle}/post/${uri.split("/").pop()}` };
}
