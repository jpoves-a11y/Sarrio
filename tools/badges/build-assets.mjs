// Genera los emblemas de la app (ios/Sarrio/Resources/Badges.xcassets) desde badges.mjs.
// PNG a 3x (600 px = 200 pt) con Geist, renderizados con Playwright: el SVG de los asset
// catalogs no pinta bien los textos. El estado bloqueado lo pinta la app (gris y progreso).
//
//   node tools/badges/build-assets.mjs
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { createRequire } from "node:module";
import { BADGES, badgeSVG } from "./badges.mjs";

const require = createRequire(import.meta.url);
const { chromium } = require("playwright");
const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.join(here, "..", "..");
const fonts = path.join(root, "ios", "Sarrio", "Resources", "Fonts");
const out = path.join(root, "ios", "Sarrio", "Resources", "Badges.xcassets");
const SIZE = 600;

fs.rmSync(out, { recursive: true, force: true });
fs.mkdirSync(out, { recursive: true });
fs.writeFileSync(path.join(out, "Contents.json"), JSON.stringify({ info: { author: "xcode", version: 1 } }, null, 2));

const face = (w, f) =>
  `@font-face{font-family:Geist;font-weight:${w};src:url(data:font/ttf;base64,${fs.readFileSync(path.join(fonts, f)).toString("base64")})}`;
const css = [face(400, "Geist-Regular.ttf"), face(500, "Geist-Medium.ttf"), face(600, "Geist-SemiBold.ttf"), face(700, "Geist-Bold.ttf")].join("");

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: SIZE, height: SIZE }, deviceScaleFactor: 1 });
for (const badge of BADGES) {
  const svg = badgeSVG(badge).replace('width="120" height="120"', `width="${SIZE}" height="${SIZE}"`);
  await page.setContent(`<html><head><style>${css}html,body{margin:0;background:transparent}</style></head><body>${svg}</body></html>`);
  await page.evaluate(() => document.fonts.ready);
  const dir = path.join(out, `badge-${badge.id}.imageset`);
  fs.mkdirSync(dir);
  await page.locator("svg").screenshot({ path: path.join(dir, `${badge.id}.png`), omitBackground: true });
  fs.writeFileSync(
    path.join(dir, "Contents.json"),
    JSON.stringify({ images: [{ idiom: "universal", filename: `${badge.id}.png`, scale: "3x" }], info: { author: "xcode", version: 1 } }, null, 2),
  );
}
await browser.close();

// Paleta de 256 colores con alfa (Pillow): un 75 % menos de peso, sin bandas visibles.
const { execFileSync } = await import("node:child_process");
execFileSync("python3", ["-c", `
import sys, glob
from PIL import Image
for f in glob.glob(sys.argv[1] + "/*/*.png"):
    Image.open(f).convert("RGBA").quantize(256, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.FLOYDSTEINBERG).save(f, optimize=True)
`, out]);
console.log(`${BADGES.length} emblemas → ${path.relative(root, out)}`);
