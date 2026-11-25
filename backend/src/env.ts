import type { Db, DbEnv } from "./db/client";
import type { AppleIdentity } from "./auth/apple";

export interface Env extends DbEnv {
  /** Secreto HMAC para los JWT de sesión propios. */
  JWT_SECRET: string;
  /** Bundle ID de la app (audiencia del token de Sign in with Apple). */
  APPLE_BUNDLE_ID: string;
  /** Clave AES (base64, 32 bytes) para cifrar tokens de proveedores. */
  TOKEN_ENCRYPTION_KEY: string;
  POLAR_CLIENT_ID?: string;
  POLAR_CLIENT_SECRET?: string;
}

/** Dependencias inyectables (en tests se sustituyen por una BD en memoria y un verificador falso). */
export interface Deps {
  getDb: (env: Env) => Db;
  verifyAppleToken: (identityToken: string, env: Env, nonce?: string) => Promise<AppleIdentity>;
}

export type AppBindings = {
  Bindings: Env;
  Variables: { db: Db; deps: Deps; userId: string };
};
