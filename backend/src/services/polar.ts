/**
 * Cliente de Polar AccessLink v3 (https://www.polar.com/accesslink-api/).
 * - OAuth 2: autorización en flow.polar.com, token en polarremote.com (no caduca en la práctica).
 * - Hay que registrar al usuario una vez (`POST /v3/users`) antes de leer sus datos.
 * - `GET /v3/exercises` lista los entrenos de los últimos 30 días; cada uno se descarga en FIT.
 */
export const POLAR_AUTHORIZE_URL = "https://flow.polar.com/oauth2/authorization";
export const POLAR_TOKEN_URL = "https://polarremote.com/v2/oauth2/token";
export const POLAR_API = "https://www.polaraccesslink.com/v3";

export type Fetch = typeof fetch;

export interface PolarConfig {
  clientId: string;
  clientSecret: string;
  redirectUri: string;
}

export class PolarError extends Error {
  constructor(
    message: string,
    readonly status: number,
  ) {
    super(message);
  }
}

export function authorizeUrl(config: PolarConfig, state: string): string {
  const params = new URLSearchParams({
    response_type: "code",
    client_id: config.clientId,
    redirect_uri: config.redirectUri,
    state,
  });
  return `${POLAR_AUTHORIZE_URL}?${params}`;
}

/** Código de autorización → token de acceso y id de usuario de Polar. */
export async function exchangeCode(fetcher: Fetch, config: PolarConfig, code: string) {
  const res = await fetcher(POLAR_TOKEN_URL, {
    method: "POST",
    headers: {
      Authorization: `Basic ${btoa(`${config.clientId}:${config.clientSecret}`)}`,
      "Content-Type": "application/x-www-form-urlencoded",
      Accept: "application/json;charset=UTF-8",
    },
    body: new URLSearchParams({ grant_type: "authorization_code", code, redirect_uri: config.redirectUri }),
  });
  if (!res.ok) throw new PolarError(`token exchange failed (${res.status})`, res.status);
  const body = (await res.json()) as { access_token?: string; x_user_id?: number | string; expires_in?: number };
  if (!body.access_token || body.x_user_id == null) throw new PolarError("token response without access_token", 502);
  return { accessToken: body.access_token, polarUserId: String(body.x_user_id), expiresIn: body.expires_in };
}

const auth = (token: string) => ({ Authorization: `Bearer ${token}` });

/** Registra al usuario en nuestra app de AccessLink (si ya lo estaba, Polar responde 409: vale igual). */
export async function registerUser(fetcher: Fetch, token: string, memberId: string) {
  const res = await fetcher(`${POLAR_API}/users`, {
    method: "POST",
    headers: { ...auth(token), "Content-Type": "application/json", Accept: "application/json" },
    body: JSON.stringify({ "member-id": memberId }),
  });
  if (!res.ok && res.status !== 409) throw new PolarError(`register failed (${res.status})`, res.status);
}

export async function deregisterUser(fetcher: Fetch, token: string, polarUserId: string) {
  const res = await fetcher(`${POLAR_API}/users/${encodeURIComponent(polarUserId)}`, { method: "DELETE", headers: auth(token) });
  if (!res.ok && res.status !== 404 && res.status !== 401) throw new PolarError(`deregister failed (${res.status})`, res.status);
}

export interface PolarExercise {
  id: string;
  startTime: string;
  utcOffsetMinutes: number | null;
  durationS: number | null;
  distanceM: number | null;
  sport: string | null;
  detailedSport: string | null;
  hasRoute: boolean;
}

/** "PT1H2M3.5S" → segundos. */
export function isoDurationSeconds(value: unknown): number | null {
  if (typeof value !== "string") return null;
  const m = /^P(?:(\d+)D)?T?(?:(\d+)H)?(?:(\d+)M)?(?:([\d.]+)S)?$/.exec(value);
  if (!m) return null;
  const [, d, h, min, s] = m;
  return Number(d ?? 0) * 86400 + Number(h ?? 0) * 3600 + Number(min ?? 0) * 60 + Number(s ?? 0);
}

export async function listExercises(fetcher: Fetch, token: string): Promise<PolarExercise[]> {
  const res = await fetcher(`${POLAR_API}/exercises`, { headers: { ...auth(token), Accept: "application/json" } });
  if (res.status === 204) return [];
  if (!res.ok) throw new PolarError(`exercises failed (${res.status})`, res.status);
  const list = (await res.json()) as Record<string, unknown>[];
  return list.map((e) => ({
    id: String(e.id),
    startTime: String(e.start_time ?? e["start-time"] ?? ""),
    utcOffsetMinutes: typeof e.start_time_utc_offset === "number" ? e.start_time_utc_offset : null,
    durationS: isoDurationSeconds(e.duration),
    distanceM: typeof e.distance === "number" ? e.distance : null,
    sport: typeof e.sport === "string" ? e.sport : null,
    detailedSport: typeof e.detailed_sport_info === "string" ? e.detailed_sport_info : null,
    hasRoute: e.has_route === true || e["has-route"] === true,
  }));
}

/** El entreno en FIT (incluye la ruta GPS si la tiene). */
export async function exerciseFit(fetcher: Fetch, token: string, id: string): Promise<ArrayBuffer> {
  const res = await fetcher(`${POLAR_API}/exercises/${encodeURIComponent(id)}/fit`, {
    headers: { ...auth(token), Accept: "*/*" },
  });
  if (!res.ok) throw new PolarError(`fit failed (${res.status})`, res.status);
  return res.arrayBuffer();
}
