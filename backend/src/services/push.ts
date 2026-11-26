import { eq, inArray } from "drizzle-orm";
import { importPKCS8, SignJWT } from "jose";
import type { Db } from "../db/client";
import { devices, users } from "../db/schema";
import type { Env } from "../env";
import { badgeCount } from "./badgeCount";
import { friendIds } from "./social";

/** Mensaje push: título, texto y a dónde lleva al tocarlo. */
export type PushMessage = { title: string; body: string; data?: Record<string, string> };

/**
 * Envío de notificaciones de una petición. Sin la clave de APNs configurada no hace nada.
 * Lo que envía no hace esperar a la respuesta (`waitUntil`).
 */
export type Pusher = {
  toUser(userId: string, message: PushMessage): void;
  /** A mis amigos (por ejemplo, «Ana ha subido el Aneto»). */
  toFriends(userId: string, message: (actorName: string) => PushMessage): void;
};

export const noPush: Pusher = { toUser() {}, toFriends() {} };

export function createPusher(env: Env, db: Db, fetchImpl: typeof fetch, waitUntil: (p: Promise<unknown>) => void): Pusher {
  if (!env.APNS_KEY || !env.APNS_KEY_ID || !env.APNS_TEAM_ID) return noPush;
  const send = (userId: string, message: PushMessage) =>
    waitUntil(sendToUser(env, db, fetchImpl, userId, message).catch((e) => console.error("push", e)));
  return {
    toUser: send,
    toFriends(userId, build) {
      waitUntil(
        (async () => {
          const [me, friends] = await Promise.all([
            db.select({ name: users.displayName }).from(users).where(eq(users.id, userId)).get(),
            friendIds(db, userId),
          ]);
          const message = build(me?.name ?? "Un amigo");
          await Promise.all(friends.map((f) => sendToUser(env, db, fetchImpl, f, message)));
        })().catch((e) => console.error("push", e)),
      );
    },
  };
}

let cachedJwt: { token: string; at: number; kid: string } | null = null;

/** JWT de proveedor (ES256), válido 1 h; se reutiliza 50 min. */
async function providerToken(env: Env) {
  if (cachedJwt && cachedJwt.kid === env.APNS_KEY_ID && Date.now() - cachedJwt.at < 50 * 60_000) return cachedJwt.token;
  const pem = env.APNS_KEY!.includes("BEGIN PRIVATE KEY")
    ? env.APNS_KEY!
    : `-----BEGIN PRIVATE KEY-----\n${env.APNS_KEY}\n-----END PRIVATE KEY-----`;
  const key = await importPKCS8(pem.replace(/\\n/g, "\n"), "ES256");
  const token = await new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: env.APNS_KEY_ID! })
    .setIssuer(env.APNS_TEAM_ID!)
    .setIssuedAt()
    .sign(key);
  cachedJwt = { token, at: Date.now(), kid: env.APNS_KEY_ID! };
  return token;
}

/** Envía a todos los iPhone de un usuario, con su número de novedades. Borra los tokens caducados. */
export async function sendToUser(env: Env, db: Db, fetchImpl: typeof fetch, userId: string, message: PushMessage) {
  const tokens = await db.select().from(devices).where(eq(devices.userId, userId));
  if (!tokens.length) return [];
  const { total } = await badgeCount(db, userId);
  const jwt = await providerToken(env);
  const payload = JSON.stringify({
    aps: { alert: { title: message.title, body: message.body }, badge: total, sound: "default" },
    ...message.data,
  });
  const dead: string[] = [];
  const results = await Promise.all(
    tokens.map(async (d) => {
      const host = d.environment === "sandbox" ? "api.sandbox.push.apple.com" : "api.push.apple.com";
      const res = await fetchImpl(`https://${host}/3/device/${d.token}`, {
        method: "POST",
        headers: {
          authorization: `bearer ${jwt}`,
          "apns-topic": env.APPLE_BUNDLE_ID,
          "apns-push-type": "alert",
          "apns-priority": "10",
          "content-type": "application/json",
        },
        body: payload,
      });
      const text = res.ok ? "" : await res.text();
      if (res.status === 410 || text.includes("BadDeviceToken") || text.includes("Unregistered")) dead.push(d.token);
      return { status: res.status, reason: text };
    }),
  );
  if (dead.length) await db.delete(devices).where(inArray(devices.token, dead));
  return results;
}
