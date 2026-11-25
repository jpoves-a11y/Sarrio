import type { DbEnv } from "./db/client";

export interface Env extends DbEnv {
  /** Bucket R2 para tracks, fotos y avatares. */
  FILES: R2Bucket;
  /** Secreto HMAC para los JWT de sesión propios. */
  JWT_SECRET: string;
  /** Bundle ID de la app (audiencia del token de Sign in with Apple). */
  APPLE_BUNDLE_ID: string;
  /** Clave AES (base64, 32 bytes) para cifrar tokens de proveedores. */
  TOKEN_ENCRYPTION_KEY: string;
  POLAR_CLIENT_ID?: string;
  POLAR_CLIENT_SECRET?: string;
}

export type AppBindings = { Bindings: Env };
