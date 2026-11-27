import { eq } from "drizzle-orm";
import type { Db } from "../db/client";
import { users } from "../db/schema";
import { newId } from "../lib/ids";
import { usernameSeed } from "../lib/validation";

export type UserRow = typeof users.$inferSelect;

/** Representación del usuario para su propio perfil. */
export function toMe(u: UserRow) {
  return {
    id: u.id,
    username: u.username,
    displayName: u.displayName,
    bio: u.bio,
    avatarKey: u.avatarKey,
    city: u.city,
    defaultVisibility: u.defaultVisibility,
    createdAt: u.createdAt.getTime(),
  };
}

/** Representación pública (lo que ve otro usuario). */
export function toPublicUser(u: UserRow) {
  return { id: u.id, username: u.username, displayName: u.displayName, bio: u.bio, avatarKey: u.avatarKey, city: u.city };
}

async function availableUsername(db: Db, seed: string): Promise<string> {
  for (let attempt = 0; attempt < 20; attempt++) {
    const candidate = attempt === 0 ? seed : `${seed}${Math.floor(Math.random() * 10_000)}`;
    const taken = await db.select({ id: users.id }).from(users).where(eq(users.username, candidate)).get();
    if (!taken) return candidate;
  }
  return `${seed}${Date.now().toString(36)}`;
}

export async function findOrCreateAppleUser(
  db: Db,
  appleSub: string,
  name?: string | null,
): Promise<{ user: UserRow; isNew: boolean }> {
  const existing = await db.select().from(users).where(eq(users.appleSub, appleSub)).get();
  if (existing) return { user: existing, isNew: false };

  const username = await availableUsername(db, usernameSeed(name));
  const [user] = await db
    .insert(users)
    .values({ id: newId(), appleSub, username, displayName: name?.trim() || username })
    .returning();
  return { user: user!, isNew: true };
}
