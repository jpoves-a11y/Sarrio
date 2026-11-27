#!/usr/bin/env node
// Diapositivas de marca (1080 × 1350, JPEG) a partir de un slides.json.
//
//   node tools/social/render.mjs marketing/queue/2026-11-30/presentacion
//
// La carpeta lleva un slides.json:
//   { "nombre": "presentacion", "fondo": "nieve" | "roca",
//     "slides": [ { "tipo": "portada", "kicker": "…", "titulo": "…", "subtitulo": "…" },
//                 { "tipo": "cifra", "kicker": "…", "cifra": "3.404", "unidad": "m", "texto": "…" },
//                 { "tipo": "texto", "kicker": "…", "texto": "…" },
//                 { "tipo": "lista", "kicker": "…", "titulo": "…", "items": ["…"] },
//                 { "tipo": "cierre", "titulo": "Cada cumbre cuenta.", "subtitulo": "…" } ] }
// y genera <nombre>-01.jpg, <nombre>-02.jpg… en la carpeta del día (la de encima).
// Cada diapositiva admite "fondo" y "atribucion" (texto pequeño abajo a la derecha, p. ej. «© OpenStreetMap»).
//
// Sin mapas de Mapbox: estas piezas se generan solas (ver brand/README.md → Mapas).

import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";
import { fileURLToPath, pathToFileURL } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const FONTS = pathToFileURL(path.join(ROOT, "ios/Sarrio/Resources/Fonts")).href;
const MARK = { nieve: "brand/sarrio-mark.svg", roca: "brand/sarrio-mark-on-dark.svg" };
const TEMPLATE = fs.readFileSync(path.join(ROOT, "tools/social/templates/slide.html"), "utf8");

const esc = (s = "") => String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);
// Saltos de línea manuales con «\n» en el JSON.
const br = (s) => esc(s).replace(/\n/g, '<span class="gap"></span>');

export function slideHtml(slide, { index, total, fondo }) {
  const mark = pathToFileURL(path.join(ROOT, MARK[fondo] ?? MARK.nieve)).href;
  const kicker = slide.kicker ? `<div class="kicker">${br(slide.kicker)}</div>` : "";
  const pie = `<div class="pie"><img src="${mark}" alt=""><span>${index} / ${total}</span></div>`;
  const atrib = slide.atribucion ? `<div class="atribucion">${esc(slide.atribucion)}</div>` : "";
  let inner;
  switch (slide.tipo) {
    case "portada":
      inner = `${kicker}<div class="titulo">${br(slide.titulo)}</div>${slide.subtitulo ? `<div class="subtitulo">${br(slide.subtitulo)}</div>` : ""}`;
      break;
    case "cifra":
      inner = `${kicker}<div class="cifra">${esc(slide.cifra)}</div>${slide.unidad ? `<div class="unidad">${esc(slide.unidad)}</div>` : ""}${slide.texto ? `<div class="subtitulo">${br(slide.texto)}</div>` : ""}`;
      break;
    case "texto":
      inner = `${kicker}<div class="texto">${br(slide.texto)}</div>`;
      break;
    case "lista":
      inner = `${kicker}${slide.titulo ? `<div class="titulo" style="font-size:72px">${br(slide.titulo)}</div>` : ""}<ul class="lista">${(slide.items ?? [])
        .map((it, i) => `<li><b>${String(i + 1).padStart(2, "0")}</b><span>${br(it)}</span></li>`)
        .join("")}</ul>`;
      break;
    case "cierre":
      return `<div class="slide cierre"><img src="${mark}" alt=""><div class="titulo">${br(slide.titulo)}</div>${slide.subtitulo ? `<div class="subtitulo">${br(slide.subtitulo)}</div>` : ""}${atrib}</div>`;
    default:
      throw new Error(`tipo de diapositiva desconocido: ${slide.tipo}`);
  }
  return `<div class="slide">${inner}${atrib}${pie}</div>`;
}

export async function render(specDir) {
  const spec = JSON.parse(fs.readFileSync(path.join(specDir, "slides.json"), "utf8"));
  const outDir = path.dirname(path.resolve(specDir));
  const name = spec.nombre ?? path.basename(specDir);
  // require (no import) para que encuentre también una instalación global de Playwright.
  const { chromium } = createRequire(import.meta.url)("playwright");
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1080, height: 1350 }, deviceScaleFactor: 1 });
  const out = [];
  try {
    for (const [i, slide] of spec.slides.entries()) {
      const fondo = slide.fondo ?? spec.fondo ?? "nieve";
      const html = TEMPLATE.replaceAll("{{FONTS}}", FONTS)
        .replace("{{FONDO}}", fondo)
        .replace("{{SLIDE}}", slideHtml(slide, { index: i + 1, total: spec.slides.length, fondo }));
      const tmp = path.join(specDir, ".render.html");
      fs.writeFileSync(tmp, html);
      await page.goto(pathToFileURL(tmp).href);
      await page.evaluate(() => document.fonts.ready);
      const file = path.join(outDir, `${name}-${String(i + 1).padStart(2, "0")}.jpg`);
      await page.screenshot({ path: file, type: "jpeg", quality: 90 });
      fs.rmSync(tmp);
      out.push(file);
    }
  } finally {
    await browser.close();
  }
  return out;
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  const dirs = process.argv.slice(2);
  if (!dirs.length) {
    console.log("Uso: render.mjs <carpeta con slides.json> [...]");
    process.exit(1);
  }
  for (const d of dirs) for (const f of await render(d)) console.log(path.relative(process.cwd(), f));
}
