import { createRemoteJWKSet, jwtVerify } from "jose";
import type { Env } from "../env";

export interface AppleIdentity {
  /** Identificador estable del usuario de Apple para este equipo de desarrollador. */
  sub: string;
  email?: string;
}

const APPLE_ISSUER = "https://appleid.apple.com";
const appleJwks = createRemoteJWKSet(new URL("https://appleid.apple.com/auth/keys"));

export async function sha256Hex(input: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(input));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

/**
 * Verifica el `identityToken` de Sign in with Apple: firma (JWKS de Apple), emisor, audiencia (bundle id),
 * caducidad y, si la app envía el nonce en claro, que coincide con el SHA-256 incluido en el token.
 */
export async function verifyAppleIdentityToken(identityToken: string, env: Env, nonce?: string): Promise<AppleIdentity> {
  const { payload } = await jwtVerify(identityToken, appleJwks, {
    issuer: APPLE_ISSUER,
    audience: env.APPLE_BUNDLE_ID,
  });
  if (nonce !== undefined && payload.nonce !== (await sha256Hex(nonce))) {
    throw new Error("nonce mismatch");
  }
  if (typeof payload.sub !== "string") throw new Error("missing sub");
  return { sub: payload.sub, email: typeof payload.email === "string" ? payload.email : undefined };
}
