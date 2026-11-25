import { createClient } from "@libsql/client/web";
import { drizzle } from "drizzle-orm/libsql";
import * as schema from "./schema";

export interface DbEnv {
  TURSO_DATABASE_URL: string;
  TURSO_AUTH_TOKEN?: string;
}

export function getDb(env: DbEnv) {
  const client = createClient({ url: env.TURSO_DATABASE_URL, authToken: env.TURSO_AUTH_TOKEN });
  return drizzle(client, { schema });
}

export type Db = ReturnType<typeof getDb>;
