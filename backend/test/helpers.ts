import { createClient } from "@libsql/client";
import { drizzle } from "drizzle-orm/libsql";
import fs from "node:fs";
import path from "node:path";
import * as schema from "../src/db/schema";
import { createApp } from "../src/app";
import type { Env } from "../src/env";
import type { Db } from "../src/db/client";

/** BD libSQL en memoria con todas las migraciones aplicadas. */
export async function createTestDb(): Promise<Db> {
  const client = createClient({ url: ":memory:" });
  const dir = path.join(__dirname, "..", "migrations");
  for (const file of fs.readdirSync(dir).filter((f) => f.endsWith(".sql")).sort()) {
    for (const stmt of fs.readFileSync(path.join(dir, file), "utf8").split("--> statement-breakpoint")) {
      if (stmt.trim()) await client.execute(stmt);
    }
  }
  await client.execute("PRAGMA foreign_keys = ON");
  return drizzle(client, { schema }) as unknown as Db;
}

export const testEnv = {
  JWT_SECRET: "test-secret-test-secret-test-secret",
  APPLE_BUNDLE_ID: "com.sarrio.test",
  TURSO_DATABASE_URL: "unused",
  // 32 bytes en base64 (AES-256)
  TOKEN_ENCRYPTION_KEY: "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=",
} as unknown as Env;

/** App con BD en memoria y un verificador de Apple falso: el token "apple:<sub>" es válido. */
export async function createTestApp(options: { fetch?: typeof fetch; env?: Partial<Env> } = {}) {
  const db = await createTestDb();
  const env = { ...testEnv, ...options.env } as Env;
  const app = createApp({
    fetch: options.fetch,
    getDb: () => db,
    verifyAppleToken: async (token) => {
      if (!token.startsWith("apple:")) throw new Error("bad token");
      return { sub: token.slice(6) };
    },
  });
  const request = (method: string, url: string, opts: { token?: string; body?: unknown } = {}) =>
    app.request(
      url,
      {
        method,
        headers: {
          "Content-Type": "application/json",
          ...(opts.token ? { Authorization: `Bearer ${opts.token}` } : {}),
        },
        body: opts.body === undefined ? undefined : JSON.stringify(opts.body),
      },
      env,
    );
  const signIn = async (sub: string, fullName?: string) => {
    const res = await request("POST", "/v1/auth/apple", { body: { identityToken: `apple:${sub}`, fullName } });
    return (await res.json()) as { token: string; isNew: boolean; user: { id: string; username: string } };
  };
  return { app, db, request, signIn };
}
