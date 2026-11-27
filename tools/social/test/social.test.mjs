import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { parsePost, validatePost, duePosts, graphemes, loadQueue } from "../lib/queue.mjs";
import { facetsFor, publishBluesky } from "../lib/bluesky.mjs";
import { publishInstagram, mediaUrl } from "../lib/instagram.mjs";

const SAMPLE = `---
red: bluesky
fecha: 2026-12-01T19:30:00+01:00
recursos: [a.jpg, "b.jpg"]
alt: Aneto al amanecer   # comentario
---
Aneto. 3.404 m. #cumbres

Funciones mencionadas: biblioteca de cumbres
`;

function tmpDay(files = {}) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "sarrio-social-"));
  const dir = path.join(root, "2026-11-30");
  fs.mkdirSync(dir);
  for (const [name, content] of Object.entries(files)) fs.writeFileSync(path.join(dir, name), content);
  return { root, dir };
}

function jsonResponse(data, status = 200) {
  return { ok: status < 400, status, json: async () => data };
}

test("parsePost lee frontmatter, listas, comentarios y separa la línea de funciones", () => {
  const p = parsePost(SAMPLE);
  assert.equal(p.meta.red, "bluesky");
  assert.deepEqual(p.meta.recursos, ["a.jpg", "b.jpg"]);
  assert.equal(p.meta.alt, "Aneto al amanecer");
  assert.equal(p.text, "Aneto. 3.404 m. #cumbres");
  assert.equal(p.features, "biblioteca de cumbres");
});

test("parsePost falla sin frontmatter", () => {
  assert.throws(() => parsePost("hola"), /frontmatter/);
});

test("graphemes cuenta emojis compuestos como uno", () => {
  assert.equal(graphemes("🏔️ ok"), 4);
});

test("validatePost exige funciones, zona horaria y límites por red", () => {
  const ok = parsePost(SAMPLE);
  assert.deepEqual(validatePost(ok), []);

  const sinFunciones = parsePost(SAMPLE.replace(/Funciones.*\n/, ""));
  assert.match(validatePost(sinFunciones).join(), /Funciones mencionadas/);

  const sinZona = parsePost(SAMPLE.replace("+01:00", ""));
  assert.match(validatePost(sinZona).join(), /zona horaria/);

  const largo = parsePost(SAMPLE.replace("Aneto.", "x".repeat(400)));
  assert.match(validatePost(largo).join(), /admite 300/);

  const igPng = parsePost(SAMPLE.replace("bluesky", "instagram-imagen").replace('[a.jpg, "b.jpg"]', "[a.png]"));
  assert.match(validatePost(igPng).join(), /JPEG/);

  const carruselCorto = parsePost(SAMPLE.replace("bluesky", "instagram-carrusel").replace('[a.jpg, "b.jpg"]', "[a.jpg]"));
  assert.match(validatePost(carruselCorto).join(), /al menos 2/);

  const reelSinVideo = parsePost(SAMPLE.replace("bluesky", "instagram-reel"));
  assert.match(validatePost(reelSinVideo).join(), /un vídeo/);
});

test("validatePost comprueba que los recursos existen", () => {
  const { dir } = tmpDay({ "a.jpg": "x" });
  assert.match(validatePost(parsePost(SAMPLE), { dir }).join(), /no existe el recurso b\.jpg/);
});

test("loadQueue y duePosts: solo lo válido, vencido y sin publicar", () => {
  const later = SAMPLE.replace("2026-12-01T19:30", "2026-12-05T19:30").replace(/recursos.*\n/, "");
  const broken = "sin frontmatter";
  const { root } = tmpDay({ "a.md": SAMPLE.replace(/recursos.*\n/, ""), "b.md": later, "c.md": broken });
  const posts = loadQueue(root);
  assert.equal(posts.length, 3);
  assert.ok(posts.find((p) => p.id === "2026-11-30/c.md").errors.length);
  const now = new Date("2026-12-02T00:00:00Z");
  assert.deepEqual(duePosts(posts, {}, now).map((p) => p.id), ["2026-11-30/a.md"]);
  assert.deepEqual(duePosts(posts, { "2026-11-30/a.md": {} }, now), []);
});

test("facetsFor marca hashtags y enlaces con posiciones en bytes", () => {
  const text = "Cima ñ #cumbres en https://sarrio.app.";
  const [tag, link] = facetsFor(text);
  const bytes = new TextEncoder().encode(text);
  const slice = (f) => new TextDecoder().decode(bytes.slice(f.index.byteStart, f.index.byteEnd));
  assert.equal(slice(tag), "#cumbres");
  assert.equal(tag.features[0].tag, "cumbres");
  assert.equal(slice(link), "https://sarrio.app");
});

test("publishBluesky inicia sesión, sube imágenes y crea el post", async () => {
  const { dir } = tmpDay({ "a.jpg": "jpegbytes" });
  const post = { id: "2026-11-30/x.md", dir, meta: { red: "bluesky", recursos: ["a.jpg"], alt: "Aneto" }, text: "Hola #cumbres" };
  const calls = [];
  const fetchImpl = async (url, init) => {
    calls.push({ url, init });
    if (url.endsWith("createSession")) return jsonResponse({ accessJwt: "jwt", did: "did:plc:1" });
    if (url.endsWith("uploadBlob")) return jsonResponse({ blob: { ref: "b1" } });
    if (url.endsWith("createRecord")) return jsonResponse({ uri: "at://did:plc:1/app.bsky.feed.post/3abc" });
    throw new Error(url);
  };
  const out = await publishBluesky(post, { env: { BLUESKY_HANDLE: "sarrio.bsky.social", BLUESKY_APP_PASSWORD: "p" }, fetchImpl });
  assert.equal(out.url, "https://bsky.app/profile/sarrio.bsky.social/post/3abc");
  const record = JSON.parse(calls[2].init.body).record;
  assert.equal(record.embed.images[0].alt, "Aneto");
  assert.equal(record.facets[0].features[0].tag, "cumbres");
  assert.equal(calls[1].init.headers.Authorization, "Bearer jwt");
});

test("publishBluesky falla sin credenciales", async () => {
  await assert.rejects(publishBluesky({ meta: {}, text: "x" }, { env: {} }), /BLUESKY_HANDLE/);
});

test("publishInstagram publica un carrusel esperando a cada contenedor", async () => {
  const post = { id: "2026-11-30/c.md", meta: { red: "instagram-carrusel", recursos: ["1.jpg", "2.jpg"] }, text: "Texto" };
  const posted = [];
  let n = 0;
  const fetchImpl = async (url, init) => {
    const u = String(url);
    if (!init) {
      if (u.includes("fields=status_code")) return jsonResponse({ status_code: "FINISHED" });
      if (u.includes("fields=permalink")) return jsonResponse({ permalink: "https://www.instagram.com/p/abc/" });
    }
    const params = Object.fromEntries(init.body);
    posted.push({ u, params });
    if (u.endsWith("/media_publish")) return jsonResponse({ id: "999" });
    return jsonResponse({ id: `c${++n}` });
  };
  const out = await publishInstagram(post, { env: { IG_USER_ID: "17", IG_ACCESS_TOKEN: "t" }, fetchImpl, sleep: async () => {} });
  assert.deepEqual(out, { id: "999", url: "https://www.instagram.com/p/abc/" });
  assert.equal(posted[0].params.is_carousel_item, "true");
  assert.equal(posted[0].params.image_url, "https://raw.githubusercontent.com/jpoves-a11y/Sarrio/main/marketing/queue/2026-11-30/1.jpg");
  assert.equal(posted[2].params.media_type, "CAROUSEL");
  assert.equal(posted[2].params.children, "c1,c2");
  assert.equal(posted[3].params.creation_id, "c3");
});

test("publishInstagram propaga un contenedor con error", async () => {
  const post = { id: "2026-11-30/i.md", meta: { red: "instagram-imagen", recursos: ["1.jpg"] }, text: "T" };
  const fetchImpl = async (url, init) => (init ? jsonResponse({ id: "c1" }) : jsonResponse({ status_code: "ERROR" }));
  await assert.rejects(
    publishInstagram(post, { env: { IG_USER_ID: "1", IG_ACCESS_TOKEN: "t" }, fetchImpl, sleep: async () => {} }),
    /ERROR/,
  );
});

test("mediaUrl respeta MEDIA_BASE_URL", () => {
  const post = { id: "2026-11-30/x.md" };
  assert.equal(mediaUrl(post, "a b.jpg", { MEDIA_BASE_URL: "https://cdn.example/q/" }), "https://cdn.example/q/2026-11-30/a%20b.jpg");
});

test("launch: fechas en hora de Madrid, con el cambio de horario", async () => {
  const { humanDate, addDays, madridOffset, fill, checkKit } = await import("../launch.mjs");
  assert.equal(humanDate("2027-03-02"), "2 de marzo");
  assert.equal(addDays("2027-03-02", -7), "2027-02-23");
  assert.equal(addDays("2027-02-27", 3), "2027-03-02");
  assert.equal(madridOffset("2027-03-27", "19:30"), "+01:00");
  assert.equal(madridOffset("2027-03-29", "19:30"), "+02:00");
  assert.equal(fill("El {{fecha}}.", "2027-10-12"), "El 12 de octubre.");
  assert.deepEqual(checkKit().errors, []);
});
