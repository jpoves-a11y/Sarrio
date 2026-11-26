import { and, eq } from "drizzle-orm";
import { Hono, type Context } from "hono";
import { jwtVerify, SignJWT } from "jose";
import type { AppBindings } from "../env";
import { requireAuth } from "../auth/session";
import { activities, providerConnections } from "../db/schema";
import { decryptToken, encryptToken } from "../lib/crypto";
import {
  authorizeUrl,
  deregisterUser,
  exchangeCode,
  exerciseFit,
  listExercises,
  PolarError,
  registerUser,
  type PolarConfig,
} from "../services/polar";

/**
 * Conexiones con proveedores. De momento Polar AccessLink:
 *
 * 1. La app pide `POST /v1/providers/polar/connect` y abre la URL devuelta (ASWebAuthenticationSession).
 * 2. Polar vuelve a `GET /v1/providers/polar/callback`; aquí se canjea el código, se registra al
 *    usuario en AccessLink, se guarda el token cifrado y se redirige a `sarrio://polar?status=…`.
 * 3. La app lista los entrenos (`GET …/exercises`), descarga cada FIT (`GET …/exercises/:id/fit`),
 *    detecta las cumbres en el iPhone y lo sube como actividad con `source: "polar"`.
 */
export const providersRoutes = new Hono<AppBindings>();

const STATE_AUDIENCE = "sarrio-polar-connect";
const APP_CALLBACK = "sarrio://polar";

type Ctx = Context<AppBindings>;

const secretKey = (c: Ctx) => new TextEncoder().encode(c.env.JWT_SECRET);
const fetcher = (c: Ctx) => c.var.deps.fetch ?? fetch;

function polarConfig(c: Ctx): PolarConfig | null {
  if (!c.env.POLAR_CLIENT_ID || !c.env.POLAR_CLIENT_SECRET) return null;
  const origin = new URL(c.req.url).origin;
  return {
    clientId: c.env.POLAR_CLIENT_ID,
    clientSecret: c.env.POLAR_CLIENT_SECRET,
    redirectUri: c.env.POLAR_REDIRECT_URI ?? `${origin}/v1/providers/polar/callback`,
  };
}

async function polarConnection(c: Ctx) {
  return c.var.db
    .select()
    .from(providerConnections)
    .where(and(eq(providerConnections.userId, c.var.userId), eq(providerConnections.provider, "polar")))
    .get();
}

/** Token de Polar del usuario (o una respuesta de error ya preparada). */
async function polarToken(c: Ctx) {
  const connection = await polarConnection(c);
  if (!connection) return { error: c.json({ error: "polar_not_connected" }, 409) };
  return { token: await decryptToken(connection.accessTokenEnc, c.env.TOKEN_ENCRYPTION_KEY), connection };
}

/** Polar respondió 401/403: el usuario revocó el acceso desde Polar Flow. */
async function handlePolarError(c: Ctx, err: unknown) {
  if (err instanceof PolarError && (err.status === 401 || err.status === 403)) {
    await c.var.db
      .delete(providerConnections)
      .where(and(eq(providerConnections.userId, c.var.userId), eq(providerConnections.provider, "polar")));
    return c.json({ error: "polar_revoked" }, 409);
  }
  console.error(err);
  return c.json({ error: "polar_unavailable" }, 502);
}

/** Estado de las conexiones. */
providersRoutes.get("/", requireAuth, async (c) => {
  const connection = await polarConnection(c);
  return c.json({
    providers: [{ provider: "polar", configured: polarConfig(c) !== null, connected: !!connection }],
  });
});

/** URL de autorización de Polar, con un `state` firmado que identifica al usuario (10 min). */
providersRoutes.post("/polar/connect", requireAuth, async (c) => {
  const config = polarConfig(c);
  if (!config) return c.json({ error: "polar_not_configured" }, 503);
  const state = await new SignJWT({})
    .setProtectedHeader({ alg: "HS256" })
    .setSubject(c.var.userId)
    .setAudience(STATE_AUDIENCE)
    .setIssuedAt()
    .setExpirationTime("10m")
    .sign(secretKey(c));
  return c.json({ url: authorizeUrl(config, state), callbackScheme: "sarrio" });
});

/** Vuelta de Polar. Sin sesión: el usuario sale del `state`. Termina redirigiendo a la app. */
providersRoutes.get("/polar/callback", async (c) => {
  const back = (status: string, reason?: string) =>
    c.redirect(`${APP_CALLBACK}?status=${status}${reason ? `&reason=${encodeURIComponent(reason)}` : ""}`, 302);
  const config = polarConfig(c);
  if (!config) return back("error", "not_configured");
  if (c.req.query("error")) return back("cancelled", c.req.query("error"));

  const code = c.req.query("code");
  const state = c.req.query("state");
  if (!code || !state) return back("error", "missing_code");

  let userId: string;
  try {
    const { payload } = await jwtVerify(state, secretKey(c), { audience: STATE_AUDIENCE, algorithms: ["HS256"] });
    if (!payload.sub) throw new Error("no sub");
    userId = payload.sub;
  } catch {
    return back("error", "invalid_state");
  }

  try {
    const { accessToken, polarUserId, expiresIn } = await exchangeCode(fetcher(c), config, code);
    await registerUser(fetcher(c), accessToken, userId);
    const db = c.var.db;
    // Una cuenta de Polar solo puede estar enlazada a un usuario de Sarrio
    const taken = await db
      .select({ userId: providerConnections.userId })
      .from(providerConnections)
      .where(and(eq(providerConnections.provider, "polar"), eq(providerConnections.externalUserId, polarUserId)))
      .get();
    if (taken && taken.userId !== userId) return back("error", "already_linked");

    const values = {
      userId,
      provider: "polar" as const,
      externalUserId: polarUserId,
      accessTokenEnc: await encryptToken(accessToken, c.env.TOKEN_ENCRYPTION_KEY),
      expiresAt: expiresIn ? new Date(Date.now() + expiresIn * 1000) : null,
    };
    await db
      .insert(providerConnections)
      .values(values)
      .onConflictDoUpdate({
        target: [providerConnections.userId, providerConnections.provider],
        set: { externalUserId: values.externalUserId, accessTokenEnc: values.accessTokenEnc, expiresAt: values.expiresAt },
      });
    return back("connected");
  } catch (err) {
    console.error(err);
    return back("error", "polar_failed");
  }
});

/** Entrenos de los últimos 30 días, marcando los ya importados. */
providersRoutes.get("/polar/exercises", requireAuth, async (c) => {
  const result = await polarToken(c);
  if ("error" in result) return result.error;
  try {
    const exercises = await listExercises(fetcher(c), result.token);
    const imported = new Set(
      (
        await c.var.db
          .select({ externalId: activities.externalId })
          .from(activities)
          .where(and(eq(activities.userId, c.var.userId), eq(activities.source, "polar")))
      ).map((r) => r.externalId),
    );
    return c.json({ exercises: exercises.map((e) => ({ ...e, imported: imported.has(e.id) })) });
  } catch (err) {
    return handlePolarError(c, err);
  }
});

/** El FIT de un entreno, tal cual lo da Polar (la app lo lee con su FITParser). */
providersRoutes.get("/polar/exercises/:id/fit", requireAuth, async (c) => {
  const id = c.req.param("id");
  if (!/^[A-Za-z0-9_-]{1,64}$/.test(id)) return c.json({ error: "invalid_id" }, 400);
  const result = await polarToken(c);
  if ("error" in result) return result.error;
  try {
    const data = await exerciseFit(fetcher(c), result.token, id);
    return c.body(data, 200, { "Content-Type": "application/octet-stream", "Cache-Control": "private, max-age=3600" });
  } catch (err) {
    return handlePolarError(c, err);
  }
});

/** Desconectar: se da de baja al usuario en AccessLink y se borra el token. Las actividades se quedan. */
providersRoutes.delete("/polar", requireAuth, async (c) => {
  const result = await polarToken(c);
  if ("error" in result) return c.body(null, 204);
  try {
    await deregisterUser(fetcher(c), result.token, result.connection.externalUserId);
  } catch (err) {
    console.error(err);
  }
  await c.var.db
    .delete(providerConnections)
    .where(and(eq(providerConnections.userId, c.var.userId), eq(providerConnections.provider, "polar")));
  return c.body(null, 204);
});
