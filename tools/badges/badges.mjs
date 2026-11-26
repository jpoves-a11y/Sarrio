// Emblemas de Sarrio: un medallón de metal grabado (bronce, plata, oro o especial) con un pictograma
// a línea fina. Una sola definición para las muestras y para los iconos vectoriales de la app.
//
//   node tools/badges/badges.mjs <carpeta>    escribe un SVG por emblema (y variantes de prueba)

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

export const TIERS = {
  bronze: { light: "#E3A06B", mid: "#B66E3A", dark: "#6B3A17", ink: "#5A2E10" },
  silver: { light: "#F4F6F8", mid: "#B9BFC7", dark: "#6E747D", ink: "#4A5058" },
  gold: { light: "#F7DE8F", mid: "#D2A23A", dark: "#86601A", ink: "#6B4A0E" },
  special: { light: "#F6A06A", mid: "#E66A29", dark: "#9C3A0E", ink: "#8A320B" },
};

// Pictogramas: trazos en una caja de 60×60 centrada en (60,60) del medallón de 120.
// `t` es el texto grabado opcional debajo del dibujo.
const P = {
  peak: "M36 78 L60 44 L84 78",
  range: "M28 80 L46 54 L56 66 L68 48 L92 80",
  flag: "M60 44 L60 28 M60 28 L72 32 L60 36",
};

export const BADGES = [
  // Cimas
  { id: "first-summit", name: "Primera cima", tier: "bronze", category: "Cimas", art: `<path d="${P.peak}"/><path d="${P.flag}"/>`, desc: "Tu primera ascensión." },
  { id: "peaks-5", name: "Cinco cimas", tier: "bronze", category: "Cimas", art: `<path d="${P.range}"/>`, t: "5", desc: "Cinco picos distintos." },
  { id: "peaks-25", name: "Veinticinco cimas", tier: "silver", category: "Cimas", art: `<path d="${P.range}"/>`, t: "25", desc: "Veinticinco picos distintos." },
  { id: "peaks-100", name: "Cien cimas", tier: "gold", category: "Cimas", art: `<path d="${P.range}"/><path d="M40 40 L44 34 L48 40 M72 38 L76 32 L80 38"/>`, t: "100", desc: "Cien picos distintos." },
  // Altura
  { id: "alt-2000", name: "Dosmil", tier: "bronze", category: "Altura", art: altitude(1), t: "2000", desc: "Una cima de 2.000 m o más." },
  { id: "alt-3000", name: "Tresmil", tier: "silver", category: "Altura", art: altitude(2), t: "3000", desc: "Una cima de 3.000 m o más." },
  { id: "alt-4000", name: "Cuatromil", tier: "special", category: "Altura", art: altitude(3), t: "4000", desc: "Una cima de 4.000 m o más." },
  // Desnivel
  { id: "gain-10k", name: "Diez mil", tier: "bronze", category: "Desnivel", art: `<path d="M44 74 L60 58 L76 74"/><path d="M44 62 L60 46 L76 62"/><path d="M44 50 L60 34 L76 50"/>`, t: "10 000", desc: "10.000 m de desnivel positivo acumulado." },
  { id: "everest", name: "Un Everest", tier: "silver", category: "Desnivel", art: `<path d="M30 80 L52 44 L60 52 L68 38 L90 80"/><path d="M62 46 L68 38 L74 48 L70 46 L66 50 Z" class="fill"/>`, t: "8849", desc: "8.849 m de desnivel positivo en una sola temporada." },
  { id: "everest-10", name: "Diez Everest", tier: "gold", category: "Desnivel", art: `<path d="M30 80 L52 44 L60 52 L68 38 L90 80"/><path d="M62 46 L68 38 L74 48 L70 46 L66 50 Z" class="fill"/>`, t: "×10", desc: "88.490 m de desnivel positivo acumulado." },
  // Distancia
  { id: "km-100", name: "Cien kilómetros", tier: "bronze", category: "Distancia", art: `<path d="M34 78 C48 78 40 62 56 62 C72 62 64 46 82 46"/><circle cx="34" cy="78" r="2.6" class="fill"/><path d="M82 46 L82 36 L90 39 L82 42"/>`, t: "100 km", desc: "100 km en salidas de montaña." },
  { id: "km-1000", name: "Mil kilómetros", tier: "gold", category: "Distancia", art: `<path d="M30 80 C42 80 36 68 48 68 C60 68 54 56 66 56 C78 56 72 44 86 44"/><circle cx="30" cy="80" r="2.6" class="fill"/><path d="M86 44 L86 34 L94 37 L86 40"/>`, t: "1000 km", desc: "1.000 km en salidas de montaña." },
  // Constancia
  { id: "streak-4", name: "Cuatro semanas", tier: "bronze", category: "Constancia", art: weeks(4), t: "4 sem.", desc: "Al menos una salida de montaña cada semana durante 4 semanas seguidas." },
  { id: "streak-12", name: "Doce semanas", tier: "silver", category: "Constancia", art: weeks(12), t: "12 sem.", desc: "Al menos una salida de montaña cada semana durante 12 semanas seguidas." },
  { id: "four-seasons", name: "Cuatro estaciones", tier: "silver", category: "Constancia", art: seasons(), desc: "Una cima en primavera, verano, otoño e invierno del mismo año." },
  // Momentos
  { id: "sunrise", name: "Madrugador", tier: "silver", category: "Momentos", art: `<path d="M30 70 L90 70"/><path d="M44 70 A16 16 0 0 1 76 70"/><path d="M60 46 L60 40 M44 52 L40 48 M76 52 L80 48 M36 62 L30 61 M84 62 L90 61"/><path d="M38 82 L50 74 L58 80 L70 72 L82 82"/>`, desc: "Una cima antes de una hora después del amanecer." },
  { id: "sunset", name: "Último rayo", tier: "silver", category: "Momentos", art: `<path d="M68 34 A16 16 0 1 0 82 56 A13 13 0 1 1 68 34 Z" class="fill"/><path d="M30 82 L50 58 L60 68 L72 54 L90 82"/><circle cx="44" cy="40" r="1.6" class="fill"/><circle cx="54" cy="32" r="1.2" class="fill"/>`, desc: "Una cima después del atardecer." },
  { id: "winter", name: "Invernal", tier: "silver", category: "Momentos", art: snowflake(60, 52, 18) + `<path d="M34 84 L60 70 L86 84"/>`, desc: "Una cima de 2.000 m o más en invierno." },
  // Esfuerzo
  { id: "chain", name: "Encadenador", tier: "silver", category: "Esfuerzo", art: `<path d="M26 80 L40 56 L50 70 L62 46 L74 66 L82 54 L94 80"/><circle cx="40" cy="56" r="2.8" class="fill"/><circle cx="62" cy="46" r="2.8" class="fill"/><circle cx="82" cy="54" r="2.8" class="fill"/>`, desc: "Tres o más cimas en una misma actividad." },
  { id: "long-day", name: "Día largo", tier: "silver", category: "Esfuerzo", art: `<path d="M30 74 A30 30 0 0 1 90 74" stroke-dasharray="3 5"/><circle cx="60" cy="44" r="6"/><path d="M28 84 L46 66 L58 76 L72 62 L92 84"/>`, t: "2000 m", desc: "2.000 m de desnivel positivo en una sola actividad." },
  { id: "ultra", name: "Ultra", tier: "gold", category: "Esfuerzo", art: `<path d="M38 60 C38 48 54 48 60 60 C66 72 82 72 82 60 C82 48 66 48 60 60 C54 72 38 72 38 60 Z"/>`, t: "40 km", desc: "40 km en una sola actividad de montaña." },
  { id: "vertical-km", name: "Kilómetro vertical", tier: "gold", category: "Esfuerzo", art: `<path d="M42 84 L42 36 L78 36"/><path d="M50 78 C56 70 54 62 60 56 C66 50 64 44 70 38"/><path d="M64 38 L70 36 L70 43"/>`, t: "1000 m", desc: "1.000 m de desnivel positivo en 5 km o menos." },
  // Montañas
  { id: "faithful", name: "Fiel", tier: "bronze", category: "Montañas", art: `<path d="${P.peak}"/><path d="M42 40 A20 20 0 0 1 78 40"/><path d="M74 34 L78 40 L71 42"/>`, t: "×5", desc: "La misma cima cinco veces." },
  { id: "explorer", name: "Explorador", tier: "silver", category: "Montañas", art: `<circle cx="60" cy="58" r="20"/><path d="M60 42 L65 58 L60 74 L55 58 Z" class="fill"/><path d="M60 34 L60 38 M60 78 L60 82 M36 58 L40 58 M80 58 L84 58"/>`, desc: "Cimas en tres cordilleras distintas." },
];

function altitude(lines) {
  let s = `<path d="M34 80 L60 40 L86 80"/>`;
  for (let i = 0; i < lines; i++) {
    const y = 72 - i * 9, half = (y - 40) * (26 / 40);
    s += `<path d="M${60 - half} ${y} L${60 + half} ${y}" stroke-dasharray="2.5 3"/>`;
  }
  return s + `<path d="M54 49 L60 40 L66 49 L62 47 L60 50 L58 47 Z" class="fill"/>`;
}

function weeks(n) {
  const cols = n <= 4 ? 4 : 4, rows = Math.ceil(n / cols);
  let s = `<rect x="34" y="34" width="52" height="${rows * 11 + 14}" rx="3"/><path d="M34 44 L86 44"/>`;
  for (let i = 0; i < n; i++) {
    const cx = 41 + (i % cols) * 12.5, cy = 52 + Math.floor(i / cols) * 11;
    s += `<path d="M${cx - 3} ${cy} L${cx - 1} ${cy + 2.5} L${cx + 3.5} ${cy - 2.5}"/>`;
  }
  return s;
}

function seasons() {
  return `<circle cx="60" cy="58" r="22"/><path d="M60 36 L60 80 M38 58 L82 58"/>` +
    // primavera: brote · verano: sol · otoño: hoja · invierno: copo
    `<path d="M49 52 C49 46 53 44 55 44 C55 48 53 51 49 52 Z M49 52 L49 47" />` +
    `<circle cx="71" cy="47" r="3.5"/><path d="M71 40 L71 41.5 M78 47 L76.5 47 M64 47 L65.5 47 M71 54 L71 52.5"/>` +
    `<path d="M50 63 C44 66 45 73 50 74 C55 73 56 66 50 63 Z M50 63 L50 74"/>` +
    snowflake(71, 69, 6);
}

function snowflake(cx, cy, r) {
  let s = "";
  for (let k = 0; k < 6; k++) {
    const a = (k * Math.PI) / 3, x = cx + r * Math.cos(a), y = cy + r * Math.sin(a);
    const b1 = a + 0.5, b2 = a - 0.5, m = 0.55;
    const mx = cx + r * m * Math.cos(a), my = cy + r * m * Math.sin(a);
    s += `<path d="M${cx} ${cy} L${x.toFixed(1)} ${y.toFixed(1)} M${mx.toFixed(1)} ${my.toFixed(1)} L${(mx + r * 0.3 * Math.cos(b1)).toFixed(1)} ${(my + r * 0.3 * Math.sin(b1)).toFixed(1)} M${mx.toFixed(1)} ${my.toFixed(1)} L${(mx + r * 0.3 * Math.cos(b2)).toFixed(1)} ${(my + r * 0.3 * Math.sin(b2)).toFixed(1)}"/>`;
  }
  return s;
}

/** SVG del emblema. `locked`: medallón en gris, sin brillo. */
export function badgeSVG(badge, { locked = false, font = "Geist" } = {}) {
  const c = locked ? { light: "#EEEFF1", mid: "#C9CCD1", dark: "#9DA1A8", ink: "#A9ADB3" } : TIERS[badge.tier];
  const id = `${badge.id}${locked ? "-l" : ""}`;
  const ticks = Array.from({ length: 48 }, (_, i) => {
    const a = (i / 48) * Math.PI * 2, r1 = 53.2, r2 = 55.6;
    return `M${(60 + r1 * Math.cos(a)).toFixed(2)} ${(60 + r1 * Math.sin(a)).toFixed(2)} L${(60 + r2 * Math.cos(a)).toFixed(2)} ${(60 + r2 * Math.sin(a)).toFixed(2)}`;
  }).join(" ");
  const label = badge.t
    ? `<text x="60" y="97" text-anchor="middle" font-family="${font}" font-weight="600" font-size="${badge.t.length > 5 ? 11 : 13}" letter-spacing="0.4" fill="${c.ink}">${badge.t}</text>`
    : "";
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 120" width="120" height="120">
  <defs>
    <linearGradient id="${id}-rim" x1="0.15" y1="0.05" x2="0.85" y2="0.95">
      <stop offset="0" stop-color="${c.light}"/><stop offset="0.45" stop-color="${c.mid}"/><stop offset="1" stop-color="${c.dark}"/>
    </linearGradient>
    <radialGradient id="${id}-face" cx="0.38" cy="0.32" r="0.8">
      <stop offset="0" stop-color="#FFFFFF"/><stop offset="0.7" stop-color="#F6F5F2"/><stop offset="1" stop-color="#E6E3DD"/>
    </radialGradient>
    <linearGradient id="${id}-gloss" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#FFFFFF" stop-opacity="${locked ? 0.15 : 0.55}"/><stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/>
    </linearGradient>
  </defs>
  <circle cx="60" cy="61.5" r="57" fill="#000" opacity="0.10"/>
  <circle cx="60" cy="60" r="57" fill="url(#${id}-rim)"/>
  <path d="${ticks}" stroke="${c.dark}" stroke-width="1" opacity="0.45"/>
  <circle cx="60" cy="60" r="50.5" fill="${c.dark}" opacity="0.55"/>
  <circle cx="60" cy="60" r="49" fill="url(#${id}-face)"/>
  <circle cx="60" cy="60" r="45.5" fill="none" stroke="${c.mid}" stroke-width="0.8" opacity="0.7"/>
  <g fill="none" stroke="${c.ink}" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" class="art" transform="translate(60 ${badge.t ? 56 : 59}) scale(1.14) translate(-60 -60)">
    ${badge.art.replaceAll('class="fill"', `fill="${c.ink}" stroke="none"`)}
  </g>
  ${label}
  <path d="M14 52 A46 46 0 0 1 106 52 A50 34 0 0 0 14 52 Z" fill="url(#${id}-gloss)"/>
</svg>`;
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  const out = process.argv[2] ?? "badges-out";
  fs.mkdirSync(out, { recursive: true });
  for (const b of BADGES) fs.writeFileSync(path.join(out, `${b.id}.svg`), badgeSVG(b));
  console.log(`${BADGES.length} emblemas → ${out}`);
}
