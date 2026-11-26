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
  // Leyendas: obsidiana mate con el grabado en oro
  legend: {
    light: "#5A5A60", mid: "#2A2A2E", dark: "#0A0A0B", ink: "#E2BC62",
    face: ["#34343A", "#1E1E22", "#121214"], ring: "#C99A3E", tick: "#C99A3E",
  },
};

/**
 * Rama de laurel a un lado de la cifra (`dir` = 1 derecha, -1 izquierda): hojas en pareja a lo
 * largo de un arco que sube desde abajo, cerca del canto.
 */
function laurel(dir, r = 42) {
  const at = (deg) => {
    const t = (deg * Math.PI) / 180; // ángulo desde arriba, en sentido horario
    return { x: 60 + dir * r * Math.sin(t), y: 60 - r * Math.cos(t), t };
  };
  const out = [];
  const a = at(140), b = at(96);
  out.push(`<path d="M${a.x.toFixed(1)} ${a.y.toFixed(1)} A${r} ${r} 0 0 ${dir > 0 ? 0 : 1} ${b.x.toFixed(1)} ${b.y.toFixed(1)}" fill="none" class="stem"/>`);
  for (let i = 0; i < 6; i++) {
    const { x, y, t } = at(137 - i * 7.5);
    const ux = -dir * Math.cos(t), uy = -Math.sin(t); // hacia arriba a lo largo de la rama
    const nx = dir * Math.sin(t), ny = -Math.cos(t); // hacia fuera
    const len = 6.4 - i * 0.45;
    for (const side of [1, -1]) {
      const ex = x + ux * len + side * nx * len * 0.55, ey = y + uy * len + side * ny * len * 0.55;
      const c1x = x + side * nx * len * 0.55, c1y = y + side * ny * len * 0.55;
      const c2x = x + ux * len * 0.7, c2y = y + uy * len * 0.7;
      out.push(`<path d="M${x.toFixed(1)} ${y.toFixed(1)} Q${c1x.toFixed(1)} ${c1y.toFixed(1)} ${ex.toFixed(1)} ${ey.toFixed(1)} Q${c2x.toFixed(1)} ${c2y.toFixed(1)} ${x.toFixed(1)} ${y.toFixed(1)} Z" class="leaf"/>`);
    }
  }
  return out.join("");
}

const CROWN = "M46 40 L46 28 L53 34 L60 24 L67 34 L74 28 L74 40 Z";

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
  // Leyendas
  { id: "king-pyrenees", name: "Rey del Pirineo", tier: "legend", category: "Leyendas", art: `<path d="${CROWN}"/><circle cx="60" cy="24" r="1.8" class="fill"/><path d="M26 82 L40 60 L48 70 L60 50 L72 66 L80 58 L94 82"/>`, t: "3000", desc: "Todos los tresmiles del Pirineo." },
  { id: "lord-alps", name: "Señor de los Alpes", tier: "legend", category: "Leyendas", art: `<path d="${CROWN}"/><circle cx="60" cy="24" r="1.8" class="fill"/><path d="M28 82 L50 60 L56 48 L62 44 L66 56 L92 82"/><path d="M56 48 L62 44 L64 52 L60 50 Z" class="fill"/>`, t: "4000", desc: "Todos los cuatromiles de los Alpes." },
  { id: "iberian-slam", name: "Gran Slam Ibérico", tier: "legend", category: "Leyendas", art: `<path d="M26 82 L32 62 L37 70 L43 54 L48 66 L54 46 L59 62 L65 50 L70 64 L76 56 L81 66 L87 60 L94 82"/>` + [[32, 62], [43, 54], [54, 46], [65, 50], [76, 56], [87, 60]].map(([x, y]) => `<circle cx="${x}" cy="${y - 5}" r="2.2" class="fill"/>`).join(""), t: "6", desc: "El techo de cada gran cordillera." },
  { id: "everesting", name: "Tenzing", tier: "legend", category: "Leyendas", art: `<path d="M28 82 L60 38 L92 82"/><path d="M48 80 L60 73 L51 66 L63 59 L56 52 L60 46" stroke-dasharray="3 3.5"/><path d="M60 38 L60 29 L69 32 L60 35"/>`, t: "8849", desc: "8.849 m de desnivel positivo en una sola actividad." },
  { id: "hundred-k", name: "Cien mil", tier: "legend", category: "Leyendas", art: `<circle cx="60" cy="58" r="22"/>` + Array.from({ length: 12 }, (_, i) => { const a = (i / 12) * Math.PI * 2; return `<path d="M${(60 + 22 * Math.sin(a)).toFixed(1)} ${(58 - 22 * Math.cos(a)).toFixed(1)} L${(60 + 25.5 * Math.sin(a)).toFixed(1)} ${(58 - 25.5 * Math.cos(a)).toFixed(1)}"/>`; }).join("") + `<path d="M46 67 L55 52 L60 59 L66 46 L75 67"/>`, t: "100 k", desc: "100.000 m de desnivel positivo en un año." },
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
  if (!locked && badge.tier === "legend") return legendSVG(badge, font);
  const c = locked ? { light: "#EEEFF1", mid: "#C9CCD1", dark: "#9DA1A8", ink: "#A9ADB3" } : TIERS[badge.tier];
  const id = `${badge.id}${locked ? "-l" : ""}`;
  const face = c.face ?? ["#FFFFFF", "#F6F5F2", "#E6E3DD"];
  // Leyendas: oro metalizado (degradado) en grabado, cifra y filos, con laurel y doble anillo
  const premium = !!c.face;
  const ink = premium ? `url(#${id}-gold)` : c.ink;
  const artScale = premium ? 0.88 : 1.14;
  const artY = premium ? (badge.t ? 53 : 58) : badge.t ? 56 : 59;
  const ticks = Array.from({ length: 48 }, (_, i) => {
    const a = (i / 48) * Math.PI * 2, r1 = 53.2, r2 = 55.6;
    return `M${(60 + r1 * Math.cos(a)).toFixed(2)} ${(60 + r1 * Math.sin(a)).toFixed(2)} L${(60 + r2 * Math.cos(a)).toFixed(2)} ${(60 + r2 * Math.sin(a)).toFixed(2)}`;
  }).join(" ");
  const label = badge.t
    ? `<text x="60" y="97" text-anchor="middle" font-family="${font}" font-weight="${premium ? 700 : 600}" font-size="${badge.t.length > 5 ? 11 : 13}" letter-spacing="${premium ? 0.8 : 0.4}" fill="${ink}">${badge.t}</text>`
    : "";
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 120" width="120" height="120">
  <defs>
    <linearGradient id="${id}-rim" x1="0.15" y1="0.05" x2="0.85" y2="0.95">
      <stop offset="0" stop-color="${c.light}"/><stop offset="0.45" stop-color="${c.mid}"/><stop offset="1" stop-color="${c.dark}"/>
    </linearGradient>
    <radialGradient id="${id}-face" cx="0.38" cy="0.32" r="0.8">
      <stop offset="0" stop-color="${face[0]}"/><stop offset="0.7" stop-color="${face[1]}"/><stop offset="1" stop-color="${face[2]}"/>
    </radialGradient>
    <linearGradient id="${id}-gold" x1="0" y1="0" x2="0.35" y2="1">
      <stop offset="0" stop-color="#FFF1C2"/><stop offset="0.35" stop-color="#EDC871"/><stop offset="0.7" stop-color="#C9963B"/><stop offset="1" stop-color="#8E6420"/>
    </linearGradient>
    <linearGradient id="${id}-gloss" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#FFFFFF" stop-opacity="${locked ? 0.15 : c.face ? 0.22 : 0.55}"/><stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/>
    </linearGradient>
  </defs>
  <circle cx="60" cy="61.5" r="57" fill="#000" opacity="0.10"/>
  <circle cx="60" cy="60" r="57" fill="url(#${id}-rim)"/>
  <path d="${ticks}" stroke="${c.tick ?? c.dark}" stroke-width="1" opacity="${c.tick ? 0.6 : 0.45}"/>
  <circle cx="60" cy="60" r="50.5" fill="${c.dark}" opacity="0.55"/>
  <circle cx="60" cy="60" r="49" fill="url(#${id}-face)"/>
  <circle cx="60" cy="60" r="45.5" fill="none" stroke="${premium ? ink : c.ring ?? c.mid}" stroke-width="${premium ? 1 : 0.8}" opacity="${premium ? 0.9 : 0.7}"/>
  ${premium ? `<circle cx="60" cy="60" r="56.6" fill="none" stroke="${ink}" stroke-width="1.1"/>
  <circle cx="60" cy="60" r="49" fill="none" stroke="${ink}" stroke-width="0.7" opacity="0.8"/>
  <circle cx="60" cy="60" r="43.8" fill="none" stroke="${ink}" stroke-width="0.4" opacity="0.6"/>
  <g fill="${ink}" stroke="${ink}" stroke-width="0.4">${laurel(1).replaceAll('class="stem"', `stroke-width="1"`)}${laurel(-1).replaceAll('class="stem"', `stroke-width="1"`)}</g>` : ""}
  <g fill="none" stroke="${ink}" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" class="art" transform="translate(60 ${artY}) scale(${artScale}) translate(-60 -60)">
    ${badge.art.replaceAll('class="fill"', `fill="${ink}" stroke="none"`)}
  </g>
  ${label}
  <path d="M14 52 A46 46 0 0 1 106 52 A50 34 0 0 0 14 52 Z" fill="url(#${id}-gloss)"/>
</svg>`;
}

/**
 * Medallón de Leyenda, como una pieza de joyería:
 * - canto chapado en oro con estrías finas y biseles de luz y sombra;
 * - esfera negra con guilloché de rayos de sol (como la esfera de un reloj) y un reflejo diagonal;
 * - pista de minutos en oro;
 * - grabado, laurel y cifra en oro en relieve, con luz especular real (filtro SVG).
 */
function legendSVG(badge, font) {
  const id = `${badge.id}-lg`;
  const P = (r, a) => [(60 + r * Math.cos(a)).toFixed(2), (60 + r * Math.sin(a)).toFixed(2)];
  const knurl = Array.from({ length: 120 }, (_, i) => {
    const a = (i / 120) * Math.PI * 2;
    return `M${P(51.6, a)} L${P(56.4, a)}`;
  }).join(" ");
  const sunray = Array.from({ length: 180 }, (_, i) => {
    const a = (i / 180) * Math.PI * 2;
    return `M${P(13, a)} L${P(48.5, a)}`;
  }).join(" ");
  const minutes = Array.from({ length: 60 }, (_, i) => {
    const a = (i / 60) * Math.PI * 2;
    const [x, y] = P(45.2, a);
    return `<circle cx="${x}" cy="${y}" r="${i % 5 === 0 ? 0.55 : 0.28}"/>`;
  }).join("");
  const label = badge.t
    ? `<text x="60" y="97.5" text-anchor="middle" font-family="${font}" font-weight="700" font-size="${badge.t.length > 5 ? 11 : 12.5}" letter-spacing="1" fill="url(#${id}-gold)">${badge.t}</text>`
    : "";
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 120" width="120" height="120">
  <defs>
    <linearGradient id="${id}-gold" x1="0" y1="0" x2="0.4" y2="1">
      <stop offset="0" stop-color="#FFF4CF"/><stop offset="0.3" stop-color="#F0CF7E"/><stop offset="0.62" stop-color="#C99A42"/><stop offset="1" stop-color="#7E5719"/>
    </linearGradient>
    <linearGradient id="${id}-rim" x1="0.1" y1="0" x2="0.9" y2="1">
      <stop offset="0" stop-color="#FFF0C4"/><stop offset="0.22" stop-color="#E7C06A"/><stop offset="0.5" stop-color="#A8792C"/>
      <stop offset="0.72" stop-color="#E9C56F"/><stop offset="1" stop-color="#6E4A14"/>
    </linearGradient>
    <radialGradient id="${id}-face" cx="0.42" cy="0.36" r="0.75">
      <stop offset="0" stop-color="#3A3A40"/><stop offset="0.55" stop-color="#1B1B1F"/><stop offset="1" stop-color="#0B0B0D"/>
    </radialGradient>
    <linearGradient id="${id}-sheen" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0.25" stop-color="#FFFFFF" stop-opacity="0"/><stop offset="0.42" stop-color="#FFFFFF" stop-opacity="0.10"/>
      <stop offset="0.5" stop-color="#FFFFFF" stop-opacity="0.02"/><stop offset="0.62" stop-color="#FFFFFF" stop-opacity="0.07"/><stop offset="0.75" stop-color="#FFFFFF" stop-opacity="0"/>
    </linearGradient>
    <clipPath id="${id}-dial"><circle cx="60" cy="60" r="49"/></clipPath>
    <filter id="${id}-emboss" x="-20%" y="-20%" width="140%" height="140%">
      <feGaussianBlur in="SourceAlpha" stdDeviation="0.55" result="blur"/>
      <feSpecularLighting in="blur" surfaceScale="2.2" specularConstant="1.1" specularExponent="22" lighting-color="#FFF6DA" result="spec">
        <fePointLight x="30" y="10" z="70"/>
      </feSpecularLighting>
      <feComposite in="spec" in2="SourceAlpha" operator="in" result="specIn"/>
      <feOffset in="SourceAlpha" dx="0.5" dy="0.8" result="off"/>
      <feGaussianBlur in="off" stdDeviation="0.5" result="shadow"/>
      <feFlood flood-color="#000" flood-opacity="0.75"/>
      <feComposite in2="shadow" operator="in" result="shadowCol"/>
      <feMerge><feMergeNode in="shadowCol"/><feMergeNode in="SourceGraphic"/><feMergeNode in="specIn"/></feMerge>
    </filter>
  </defs>
  <circle cx="60" cy="62" r="57.5" fill="#000" opacity="0.28"/>
  <!-- Canto de oro con estrías y biseles -->
  <circle cx="60" cy="60" r="57.5" fill="url(#${id}-rim)"/>
  <path d="${knurl}" stroke="#4A300A" stroke-width="0.45" opacity="0.45"/>
  <circle cx="60" cy="60" r="57.1" fill="none" stroke="#FFF7DD" stroke-width="0.6" opacity="0.7"/>
  <circle cx="60" cy="60" r="50.9" fill="none" stroke="#3B2706" stroke-width="1.4" opacity="0.8"/>
  <!-- Esfera negra con guilloché de rayos -->
  <circle cx="60" cy="60" r="49.6" fill="url(#${id}-face)"/>
  <g clip-path="url(#${id}-dial)">
    <path d="${sunray}" stroke="#FFFFFF" stroke-width="0.35" opacity="0.06"/>
    <circle cx="60" cy="60" r="49" fill="url(#${id}-sheen)"/>
  </g>
  <circle cx="60" cy="60" r="49.6" fill="none" stroke="#000" stroke-width="1" opacity="0.6"/>
  <!-- Pista de minutos -->
  <g filter="url(#${id}-emboss)">
    <circle cx="60" cy="60" r="47" fill="none" stroke="url(#${id}-gold)" stroke-width="0.8"/>
    <circle cx="60" cy="60" r="43.4" fill="none" stroke="url(#${id}-gold)" stroke-width="0.45"/>
    <g fill="url(#${id}-gold)">${minutes}</g>
    <g fill="url(#${id}-gold)" stroke="url(#${id}-gold)" stroke-width="0.4">${laurel(1, 39.5).replaceAll('class="stem"', 'stroke-width="1"')}${laurel(-1, 39.5).replaceAll('class="stem"', 'stroke-width="1"')}</g>
    <g fill="none" stroke="url(#${id}-gold)" stroke-width="2.7" stroke-linecap="round" stroke-linejoin="round" transform="translate(60 ${badge.t ? 53 : 58}) scale(0.84) translate(-60 -60)">
      ${badge.art.replaceAll('class="fill"', `fill="url(#${id}-gold)" stroke="none"`)}
    </g>
    ${label}
  </g>
  <!-- Brillo del cristal -->
  <path d="M16 50 A45 45 0 0 1 104 50 A52 36 0 0 0 16 50 Z" fill="#FFFFFF" opacity="0.07"/>
</svg>`;
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  const out = process.argv[2] ?? "badges-out";
  fs.mkdirSync(out, { recursive: true });
  for (const b of BADGES) fs.writeFileSync(path.join(out, `${b.id}.svg`), badgeSVG(b));
  console.log(`${BADGES.length} emblemas → ${out}`);
}
