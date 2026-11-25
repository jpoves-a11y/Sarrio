import { jwtVerify, SignJWT } from "jose";
import { createMiddleware } from "hono/factory";
import type { AppBindings } from "../env";

const ISSUER = "sarrio";
const SESSION_TTL = "60d";

const key = (secret: string) => new TextEncoder().encode(secret);

export async function issueSessionToken(userId: string, secret: string): Promise<string> {
  return new SignJWT({})
    .setProtectedHeader({ alg: "HS256" })
    .setSubject(userId)
    .setIssuer(ISSUER)
    .setIssuedAt()
    .setExpirationTime(SESSION_TTL)
    .sign(key(secret));
}

export async function verifySessionToken(token: string, secret: string): Promise<string> {
  const { payload } = await jwtVerify(token, key(secret), { issuer: ISSUER, algorithms: ["HS256"] });
  if (!payload.sub) throw new Error("missing sub");
  return payload.sub;
}

/** Exige `Authorization: Bearer <jwt>` y deja el id de usuario en `c.var.userId`. */
export const requireAuth = createMiddleware<AppBindings>(async (c, next) => {
  const header = c.req.header("Authorization");
  const token = header?.startsWith("Bearer ") ? header.slice(7) : undefined;
  if (!token) return c.json({ error: "unauthorized" }, 401);
  try {
    c.set("userId", await verifySessionToken(token, c.env.JWT_SECRET));
  } catch {
    return c.json({ error: "unauthorized" }, 401);
  }
  await next();
});
