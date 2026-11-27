import { and, eq, inArray, or } from "drizzle-orm";
import type { Db } from "../db/client";
import { blocks, feedItems, friendships, notifications, users, type Visibility } from "../db/schema";
import { newId } from "../lib/ids";

/** Estado de amistad visto desde `me`. */
export type FriendStatus = "none" | "friends" | "outgoing" | "incoming" | "blocked";

export async function friendStatus(db: Db, me: string, other: string): Promise<FriendStatus> {
  if (await isBlockedEitherWay(db, me, other)) return "blocked";
  const row = await db
    .select()
    .from(friendships)
    .where(
      or(
        and(eq(friendships.requesterId, me), eq(friendships.addresseeId, other)),
        and(eq(friendships.requesterId, other), eq(friendships.addresseeId, me)),
      ),
    )
    .get();
  if (!row) return "none";
  if (row.status === "accepted") return "friends";
  return row.requesterId === me ? "outgoing" : "incoming";
}

export async function isBlockedEitherWay(db: Db, a: string, b: string) {
  const row = await db
    .select({ id: blocks.blockerId })
    .from(blocks)
    .where(or(and(eq(blocks.blockerId, a), eq(blocks.blockedId, b)), and(eq(blocks.blockerId, b), eq(blocks.blockedId, a))))
    .get();
  return !!row;
}

/** Ids de mis amigos (amistades aceptadas). */
export async function friendIds(db: Db, me: string): Promise<string[]> {
  const rows = await db
    .select({ requesterId: friendships.requesterId, addresseeId: friendships.addresseeId })
    .from(friendships)
    .where(and(eq(friendships.status, "accepted"), or(eq(friendships.requesterId, me), eq(friendships.addresseeId, me))));
  return rows.map((r) => (r.requesterId === me ? r.addresseeId : r.requesterId));
}

/** Usuarios con los que hay un bloqueo, en cualquier sentido. */
export async function blockedIds(db: Db, me: string): Promise<Set<string>> {
  const rows = await db
    .select({ blockerId: blocks.blockerId, blockedId: blocks.blockedId })
    .from(blocks)
    .where(or(eq(blocks.blockerId, me), eq(blocks.blockedId, me)));
  return new Set(rows.map((r) => (r.blockerId === me ? r.blockedId : r.blockerId)));
}

export const publicUserColumns = {
  id: users.id,
  username: users.username,
  displayName: users.displayName,
  bio: users.bio,
  avatarKey: users.avatarKey,
  city: users.city,
};

export async function displayName(db: Db, id: string) {
  const row = await db.select({ name: users.displayName }).from(users).where(eq(users.id, id)).get();
  return row?.name ?? "Alguien";
}

export async function publicUsers(db: Db, ids: string[]) {
  if (!ids.length)
    return new Map<string, { id: string; username: string; displayName: string; bio: string | null; avatarKey: string | null; city: string | null }>();
  const rows = await db.select(publicUserColumns).from(users).where(inArray(users.id, [...new Set(ids)]));
  return new Map(rows.map((u) => [u.id, u]));
}

type NotificationKind = (typeof notifications.$inferInsert)["kind"];

/** Aviso para otro usuario (nunca para uno mismo). */
export async function notify(
  db: Db,
  n: { userId: string; actorId: string; kind: NotificationKind; targetType?: string; targetId?: string },
) {
  if (n.userId === n.actorId) return;
  await db.insert(notifications).values({ id: newId(), ...n, targetType: n.targetType ?? null, targetId: n.targetId ?? null });
}

/** Elemento del feed. `at` es cuándo ocurrió (la cima, la salida, el emblema), no cuándo se subió. */
export async function addFeedItem(
  db: Db,
  item: { actorId: string; kind: (typeof feedItems.$inferInsert)["kind"]; refId: string; visibility: Visibility; at: number },
) {
  await db.insert(feedItems).values({
    id: newId(),
    actorId: item.actorId,
    kind: item.kind,
    refId: item.refId,
    visibility: item.visibility,
    createdAt: new Date(item.at),
    insertedAt: new Date(),
  });
}

/** Cambia la visibilidad de los elementos del feed de un contenido (al editar la actividad o la ascensión). */
export async function setFeedVisibility(db: Db, kind: "activity" | "ascent", refId: string, visibility: Visibility) {
  await db.update(feedItems).set({ visibility }).where(and(eq(feedItems.kind, kind), eq(feedItems.refId, refId)));
}

export async function removeFeedItems(db: Db, kind: "activity" | "ascent", refId: string) {
  await db.delete(feedItems).where(and(eq(feedItems.kind, kind), eq(feedItems.refId, refId)));
}
