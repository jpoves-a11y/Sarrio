import type { ChallengeMetric } from "../db/schema";

export type Tier = "bronze" | "silver" | "gold" | "special" | "legend";

/** Catálogo de emblemas. Los dibujos están en `tools/badges/badges.mjs` (mismo `id`). */
export const BADGES: { id: string; name: string; description: string; tier: Tier; category: string }[] = [
  { id: "first-summit", name: "Primera cima", tier: "bronze", category: "Cimas", description: "Tu primera ascensión." },
  { id: "peaks-5", name: "Cinco cimas", tier: "bronze", category: "Cimas", description: "Cinco picos distintos." },
  { id: "peaks-25", name: "Veinticinco cimas", tier: "silver", category: "Cimas", description: "Veinticinco picos distintos." },
  { id: "peaks-100", name: "Cien cimas", tier: "gold", category: "Cimas", description: "Cien picos distintos." },
  { id: "alt-2000", name: "Dosmil", tier: "bronze", category: "Altura", description: "Una cima de 2.000 m o más." },
  { id: "alt-3000", name: "Tresmil", tier: "silver", category: "Altura", description: "Una cima de 3.000 m o más." },
  { id: "alt-4000", name: "Cuatromil", tier: "special", category: "Altura", description: "Una cima de 4.000 m o más." },
  { id: "gain-10k", name: "Diez mil", tier: "bronze", category: "Desnivel", description: "10.000 m de desnivel positivo acumulado." },
  { id: "everest", name: "Un Everest", tier: "silver", category: "Desnivel", description: "8.849 m de desnivel positivo en un mismo año." },
  { id: "everest-10", name: "Diez Everest", tier: "gold", category: "Desnivel", description: "88.490 m de desnivel positivo acumulado." },
  { id: "km-100", name: "Cien kilómetros", tier: "bronze", category: "Distancia", description: "100 km en salidas de montaña." },
  { id: "km-1000", name: "Mil kilómetros", tier: "gold", category: "Distancia", description: "1.000 km en salidas de montaña." },
  { id: "streak-4", name: "Cuatro semanas", tier: "bronze", category: "Constancia", description: "Al menos una salida de montaña cada semana durante 4 semanas seguidas." },
  { id: "streak-12", name: "Doce semanas", tier: "silver", category: "Constancia", description: "Al menos una salida de montaña cada semana durante 12 semanas seguidas." },
  { id: "four-seasons", name: "Cuatro estaciones", tier: "silver", category: "Constancia", description: "Una cima en primavera, verano, otoño e invierno del mismo año." },
  { id: "sunrise", name: "Madrugador", tier: "silver", category: "Momentos", description: "Una cima antes de que pase una hora del amanecer." },
  { id: "sunset", name: "Último rayo", tier: "silver", category: "Momentos", description: "Una cima después del atardecer." },
  { id: "winter", name: "Invernal", tier: "silver", category: "Momentos", description: "Una cima de 2.000 m o más en invierno." },
  { id: "chain", name: "Encadenador", tier: "silver", category: "Esfuerzo", description: "Tres o más cimas en una misma actividad." },
  { id: "long-day", name: "Día largo", tier: "silver", category: "Esfuerzo", description: "2.000 m de desnivel positivo en una sola actividad." },
  { id: "ultra", name: "Ultra", tier: "gold", category: "Esfuerzo", description: "40 km en una sola actividad de montaña." },
  { id: "vertical-km", name: "Kilómetro vertical", tier: "gold", category: "Esfuerzo", description: "1.000 m de desnivel positivo en 5 km o menos." },
  { id: "faithful", name: "Fiel", tier: "bronze", category: "Montañas", description: "La misma cima cinco veces." },
  { id: "explorer", name: "Explorador", tier: "silver", category: "Montañas", description: "Cimas en tres cordilleras distintas." },
  // Leyendas: retos de toda una vida (los de lista se ganan al completar su reto, ver `badge_id`)
  { id: "king-pyrenees", name: "Rey del Pirineo", tier: "legend", category: "Leyendas", description: "Todos los tresmiles del Pirineo." },
  { id: "lord-alps", name: "Señor de los Alpes", tier: "legend", category: "Leyendas", description: "Todos los cuatromiles de los Alpes." },
  { id: "iberian-slam", name: "Gran Slam Ibérico", tier: "legend", category: "Leyendas", description: "El techo de cada gran cordillera: Aneto, Mulhacén, Torre Cerredo, Almanzor, Moncayo y Teide." },
  { id: "everesting", name: "Everesting", tier: "legend", category: "Leyendas", description: "8.849 m de desnivel positivo en una sola actividad." },
  { id: "hundred-k", name: "Cien mil", tier: "legend", category: "Leyendas", description: "100.000 m de desnivel positivo en un mismo año." },
];

/** Emblemas de Leyenda que se ganan al completar un reto de lista de cimas (`challenges.badge_id`). */
export const LIST_LEGENDS = ["king-pyrenees", "lord-alps", "iberian-slam"];

export type OfficialMetricChallenge = {
  slug: string;
  badgeId?: string;
  title: string;
  description: string;
  metric: ChallengeMetric;
  target: number;
  recurrence: "none" | "monthly" | "yearly";
  window?: string;
  sport?: string;
  minEle?: number;
};

/** Retos oficiales de meta (esfuerzo y constancia). Los de lista de cimas los siembra `scripts/seed-challenges.mjs`. */
export const METRIC_CHALLENGES: OfficialMetricChallenge[] = [
  { slug: "everest-year", title: "Un Everest este año", description: "Acumula 8.849 m de desnivel positivo durante el año.", metric: "elevation_gain", target: 8849, recurrence: "yearly" },
  { slug: "gain-month", title: "Desnivel del mes", description: "5.000 m de desnivel positivo en un mes.", metric: "elevation_gain", target: 5000, recurrence: "monthly" },
  { slug: "weeks-52", title: "52 semanas de montaña", description: "Al menos una salida en cada una de las 52 semanas del año.", metric: "active_weeks", target: 52, recurrence: "yearly" },
  { slug: "summits-30", title: "Treinta cimas", description: "Treinta cimas en el año, se cuentan también las repetidas.", metric: "summits", target: 30, recurrence: "yearly" },
  { slug: "summer-high", title: "Verano en altura", description: "Cinco cimas de 3.000 m o más entre el 21 de junio y el 22 de septiembre.", metric: "high_summits", target: 5, minEle: 3000, recurrence: "yearly", window: "06-21..09-22" },
  { slug: "white-winter", title: "Invierno blanco", description: "Diez salidas de montaña entre el 21 de diciembre y el 20 de marzo.", metric: "activities", target: 10, recurrence: "yearly", window: "12-21..03-20" },
  { slug: "summer-100k", title: "Cien kilómetros de verano", description: "100 km de montaña de junio a septiembre.", metric: "distance", target: 100_000, recurrence: "yearly", window: "06-01..09-30" },
  { slug: "trail-vertical", title: "Trail vertical", description: "10.000 m de desnivel positivo corriendo por montaña en el año.", metric: "elevation_gain", target: 10_000, sport: "trail_running", recurrence: "yearly" },
  { slug: "sunrises", title: "Madrugadas", description: "Cinco cimas al amanecer en el año.", metric: "sunrise_summits", target: 5, recurrence: "yearly" },
  { slug: "month-nonstop", title: "Mes sin parar", description: "Una salida de montaña cada semana del mes.", metric: "active_weeks", target: 4, recurrence: "monthly" },
];

/** Leyendas de meta (las de lista las siembra `scripts/seed-challenges.mjs`). */
export const LEGEND_METRIC_CHALLENGES: OfficialMetricChallenge[] = [
  { slug: "legend-everesting", badgeId: "everesting", title: "Everesting", description: "La altura del Everest, 8.849 m de desnivel positivo, en una sola actividad.", metric: "max_activity_gain", target: 8849, recurrence: "none" },
  { slug: "legend-hundred-k", badgeId: "hundred-k", title: "Cien mil", description: "100.000 m de desnivel positivo en un año: más de once Everest.", metric: "elevation_gain", target: 100_000, recurrence: "yearly" },
];
