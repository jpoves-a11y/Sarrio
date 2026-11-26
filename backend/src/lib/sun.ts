/**
 * Elevación del sol sobre el horizonte, en grados (negativa bajo él).
 * Ecuaciones de posición solar de la NOAA: el mismo cálculo que `SarrioKit.SunPosition`.
 */
export function sunElevation(lat: number, lon: number, ms: number): number {
  const r = Math.PI / 180;
  const julianDay = ms / 86_400_000 + 2_440_587.5;
  const t = (julianDay - 2_451_545) / 36_525;
  const meanLongitude = (280.46646 + t * (36_000.76983 + t * 0.0003032)) % 360;
  const meanAnomaly = 357.52911 + t * (35_999.05029 - 0.0001537 * t);
  const eccentricity = 0.016708634 - t * (0.000042037 + 0.0000001267 * t);
  const m = meanAnomaly * r;
  const center =
    Math.sin(m) * (1.914602 - t * (0.004817 + 0.000014 * t)) + Math.sin(2 * m) * (0.019993 - 0.000101 * t) + Math.sin(3 * m) * 0.000289;
  const omega = (125.04 - 1934.136 * t) * r;
  const longitude = (meanLongitude + center - 0.00569 - 0.00478 * Math.sin(omega)) * r;
  const obliquity0 = 23 + (26 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60) / 60;
  const obliquity = (obliquity0 + 0.00256 * Math.cos(omega)) * r;
  const declination = Math.asin(Math.sin(obliquity) * Math.sin(longitude));
  const y = Math.tan(obliquity / 2) ** 2;
  const l0 = meanLongitude * r;
  const equationOfTime =
    (4 / r) *
    (y * Math.sin(2 * l0) -
      2 * eccentricity * Math.sin(m) +
      4 * eccentricity * y * Math.sin(m) * Math.cos(2 * l0) -
      0.5 * y * y * Math.sin(4 * l0) -
      1.25 * eccentricity * eccentricity * Math.sin(2 * m));
  const minutes = ((julianDay + 0.5) % 1) * 1440;
  let trueSolarTime = (minutes + equationOfTime + 4 * lon) % 1440;
  if (trueSolarTime < 0) trueSolarTime += 1440;
  let hourAngle = trueSolarTime / 4 - 180;
  if (hourAngle < -180) hourAngle += 360;
  const latitude = lat * r;
  const cosZenith =
    Math.sin(latitude) * Math.sin(declination) + Math.cos(latitude) * Math.cos(declination) * Math.cos(hourAngle * r);
  return 90 - Math.acos(Math.min(1, Math.max(-1, cosZenith))) / r;
}

const rising = (lat: number, lon: number, ms: number) => sunElevation(lat, lon, ms + 600_000) > sunElevation(lat, lon, ms);

/**
 * Cima al amanecer: el sol sube y aún no ha pasado una hora desde que salió
 * (≈ 8° sobre el horizonte), contando desde el alba náutica (−12°).
 */
export function isSunriseSummit(lat: number, lon: number, ms: number): boolean {
  const e = sunElevation(lat, lon, ms);
  return e > -12 && e <= 8 && rising(lat, lon, ms);
}

/** Cima tras la puesta: el sol baja y ya está bajo el horizonte (hasta el anochecer astronómico, −18°). */
export function isSunsetSummit(lat: number, lon: number, ms: number): boolean {
  const e = sunElevation(lat, lon, ms);
  return e < -0.833 && e > -18 && !rising(lat, lon, ms);
}
