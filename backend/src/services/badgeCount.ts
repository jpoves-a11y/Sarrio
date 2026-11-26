import { and, count, eq, inArray, isNull, ne, sql } from "drizzle-orm";
import type { Db } from "../db/client";
import { feedItems, notifications, users } from "../db/schema";
import { friendIds } from "./social";

/**
 * Novedades para el número del icono: avisos sin leer más lo que mis amigos han hecho desde la
 * última vez que abrí Amigos (solo lo que pueden ver los amigos: no lo privado).
 */
export async function badgeCount(db: Db, userId: string) {
  const [unread, me, friends] = await Promise.all([
    db
      .select({ n: count() })
      .from(notifications)
      .where(and(eq(notifications.userId, userId), isNull(notifications.readAt)))
      .get(),
    db.select({ seen: users.feedSeenAt, created: users.createdAt }).from(users).where(eq(users.id, userId)).get(),
    friendIds(db, userId),
  ]);
  let feed = 0;
  if (friends.length) {
    // Sin fecha de última visita: desde que se creó la cuenta (no todo el pasado de los amigos)
    const since = me?.seen ?? me?.created ?? new Date();
    const row = await db
      .select({ n: count() })
      .from(feedItems)
      .where(and(inArray(feedItems.actorId, friends), ne(feedItems.visibility, "private"), sql`coalesce(${feedItems.insertedAt}, ${feedItems.createdAt}) > ${since.getTime()}`))
      .get();
    feed = row?.n ?? 0;
  }
  const notificationsCount = unread?.n ?? 0;
  return { notifications: notificationsCount, feed, total: notificationsCount + feed };
}
