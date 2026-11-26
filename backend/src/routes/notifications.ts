import { and, desc, eq, inArray, isNull } from "drizzle-orm";
import { Hono } from "hono";
import type { AppBindings } from "../env";
import { requireAuth } from "../auth/session";
import { feedItems, notifications } from "../db/schema";
import { publicUsers } from "../services/social";
import { feedItemLabel } from "./feed";

export const notificationsRoutes = new Hono<AppBindings>();
notificationsRoutes.use("*", requireAuth);

/** Mis avisos (los 50 últimos), con quién los hizo y una línea de lo que tocan. */
notificationsRoutes.get("/", async (c) => {
  const db = c.var.db;
  const rows = await db
    .select()
    .from(notifications)
    .where(eq(notifications.userId, c.var.userId))
    .orderBy(desc(notifications.createdAt), desc(notifications.id))
    .limit(50);
  const people = await publicUsers(db, rows.flatMap((r) => (r.actorId ? [r.actorId] : [])));
  const itemIds = rows.filter((r) => r.targetType === "feed_item" && r.targetId).map((r) => r.targetId!);
  const items = itemIds.length ? await db.select().from(feedItems).where(inArray(feedItems.id, itemIds)) : [];
  const labels = new Map<string, string | null>();
  for (const item of items) labels.set(item.id, await feedItemLabel(db, item));
  const unread = rows.filter((r) => !r.readAt).length;
  return c.json({
    unread,
    notifications: rows
      .filter((r) => !r.actorId || people.has(r.actorId))
      .map((r) => ({
        id: r.id,
        kind: r.kind,
        actor: r.actorId ? people.get(r.actorId)! : null,
        targetType: r.targetType,
        targetId: r.targetId,
        label: r.targetId ? (labels.get(r.targetId) ?? null) : null,
        read: !!r.readAt,
        createdAt: r.createdAt.getTime(),
      })),
  });
});

/** Marcar todo como leído. */
notificationsRoutes.post("/read", async (c) => {
  await c.var.db
    .update(notifications)
    .set({ readAt: new Date() })
    .where(and(eq(notifications.userId, c.var.userId), isNull(notifications.readAt)));
  return c.json({ unread: 0 });
});
