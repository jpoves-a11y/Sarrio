import { Hono } from "hono";
import type { AppBindings } from "../env";
import { issueSessionToken } from "../auth/session";
import { findOrCreateAppleUser, toMe } from "../services/users";

export const authRoutes = new Hono<AppBindings>();

/**
 * Sign in with Apple. Body: `{ identityToken, nonce?, fullName? }`.
 * Apple solo envía el nombre la PRIMERA vez que el usuario autoriza la app, por eso la app lo reenvía aquí.
 */
authRoutes.post("/apple", async (c) => {
  const body = await c.req.json<{ identityToken?: string; nonce?: string; fullName?: string }>().catch(() => null);
  if (!body?.identityToken) return c.json({ error: "identityToken required" }, 400);

  let identity;
  try {
    identity = await c.var.deps.verifyAppleToken(body.identityToken, c.env, body.nonce);
  } catch {
    return c.json({ error: "invalid_identity_token" }, 401);
  }

  const { user, isNew } = await findOrCreateAppleUser(c.var.db, identity.sub, body.fullName);
  const token = await issueSessionToken(user.id, c.env.JWT_SECRET);
  return c.json({ token, isNew, user: toMe(user) }, isNew ? 201 : 200);
});
