import { and, asc, count, desc, eq, inArray, lt } from "drizzle-orm";
import { Hono } from "hono";
import type { AppBindings } from "../env";
import type { Db } from "../db/client";
import { requireAuth } from "../auth/session";
import { activities, activityTracks, ascents, badges, challenges, comments, feedItems, likes, privacyZones, users } from "../db/schema";
import { badgeCount } from "../services/badgeCount";
import { applyPrivacyZones } from "../lib/geo";
import { decodeTrack } from "../lib/track";
import { newId } from "../lib/ids";
import { ascentsForActivities, ascentsWithPeaks, toActivity } from "../services/activities";
import { getRelationship } from "../services/relationships";
import { displayName, friendIds, notify, publicUsers } from "../services/social";
import { canView } from "../services/visibility";

type FeedRow = typeof feedItems.$inferSelect;

/** Elemento del feed ya completado: según `kind` lleva actividad y cimas, cimas, emblema o reto. */
export type FeedEntry = {
  id: string;
  kind: FeedRow["kind"];
  at: number;
  visibility: FeedRow["visibility"];
  actor: { id: string; username: string; displayName: string; bio: string | null; avatarKey: string | null };
  likeCount: number;
  commentCount: number;
  likedByMe: boolean;
  activity?: ReturnType<typeof toActivity>;
  /** Vista previa de la ruta para el mapa 3D del feed: tramos de `[lat, lon]`, ya sin zonas privadas. */
  route?: number[][][];
  ascents?: Awaited<ReturnType<typeof ascentsWithPeaks>>;
  badge?: { id: string; name: string; description: string; tier: string; category: string; icon: string };
  challenge?: { id: string; slug: string | null; title: string; kind: string; badgeId: string | null; official: boolean };
};

/** El elemento del feed, si quien mira puede verlo. */
export async function visibleFeedItem(db: Db, viewerId: string, id: string): Promise<FeedRow | null> {
  const item = await db.select().from(feedItems).where(eq(feedItems.id, id)).get();
  if (!item) return null;
  const rel = await getRelationship(db, viewerId, item.actorId);
  return canView(item.visibility, rel) ? item : null;
}

/**
 * Completa los elementos del feed con su contenido (actividad y cimas, ascensión, emblema o reto),
 * los likes y los comentarios. Los que ya no existen (actividad borrada…) se descartan.
 */
export async function hydrateFeed(db: Db, viewerId: string, items: FeedRow[]): Promise<FeedEntry[]> {
  if (!items.length) return [];
  const ids = (kind: FeedRow["kind"]) => items.filter((i) => i.kind === kind).map((i) => i.refId);
  const activityIds = ids("activity");
  const [actRows, actAscents, manual, badgeRows, challengeRows, people, likeRows, commentRows, mine] = await Promise.all([
    activityIds.length ? db.select().from(activities).where(inArray(activities.id, activityIds)) : Promise.resolve([]),
    ascentsForActivities(db, activityIds),
    ids("ascent").length ? ascentsWithPeaks(db, and(inArray(ascents.id, ids("ascent")))) : Promise.resolve([]),
    ids("badge").length ? db.select().from(badges).where(inArray(badges.id, ids("badge"))) : Promise.resolve([]),
    ids("challenge_completed").length
      ? db.select().from(challenges).where(inArray(challenges.id, ids("challenge_completed")))
      : Promise.resolve([]),
    publicUsers(db, items.map((i) => i.actorId)),
    db
      .select({ id: likes.targetId, n: count() })
      .from(likes)
      .where(and(eq(likes.targetType, "feed_item"), inArray(likes.targetId, items.map((i) => i.id))))
      .groupBy(likes.targetId),
    db
      .select({ id: comments.targetId, n: count() })
      .from(comments)
      .where(and(eq(comments.targetType, "feed_item"), inArray(comments.targetId, items.map((i) => i.id))))
      .groupBy(comments.targetId),
    db
      .select({ id: likes.targetId })
      .from(likes)
      .where(and(eq(likes.userId, viewerId), eq(likes.targetType, "feed_item"), inArray(likes.targetId, items.map((i) => i.id)))),
  ]);
  const acts = new Map(actRows.map((a) => [a.id, a]));
  const routes = await previewRoutes(db, viewerId, actRows);
  const manualMap = new Map(manual.map((a) => [a.id, a]));
  const badgeMap = new Map(badgeRows.map((b) => [b.id, b]));
  const challengeMap = new Map(challengeRows.map((c) => [c.id, c]));
  const likeCount = new Map(likeRows.map((r) => [r.id, r.n]));
  const commentCount = new Map(commentRows.map((r) => [r.id, r.n]));
  const liked = new Set(mine.map((r) => r.id));

  return items.flatMap((item): FeedEntry[] => {
    const actor = people.get(item.actorId);
    if (!actor) return [];
    const base: FeedEntry = {
      id: item.id,
      kind: item.kind,
      at: item.createdAt.getTime(),
      visibility: item.visibility,
      actor,
      likeCount: likeCount.get(item.id) ?? 0,
      commentCount: commentCount.get(item.id) ?? 0,
      likedByMe: liked.has(item.id),
    };
    switch (item.kind) {
      case "activity": {
        const a = acts.get(item.refId);
        if (!a) return [];
        return [
          {
            ...base,
            activity: toActivity(a, { includeBox: a.userId === viewerId }),
            ascents: actAscents.filter((x) => x.activityId === a.id),
            route: routes.get(a.id),
          },
        ];
      }
      case "ascent": {
        const a = manualMap.get(item.refId);
        return a ? [{ ...base, ascents: [a] }] : [];
      }
      case "badge": {
        const b = badgeMap.get(item.refId);
        return b ? [{ ...base, badge: { id: b.id, name: b.name, description: b.description, tier: b.tier, category: b.category, icon: b.icon } }] : [];
      }
      case "challenge_completed": {
        const c = challengeMap.get(item.refId);
        return c ? [{ ...base, challenge: { id: c.id, slug: c.slug, title: c.title, kind: c.kind, badgeId: c.badgeId, official: c.creatorId == null } }] : [];
      }
    }
  });
}

const PREVIEW_POINTS = 150;

/**
 * Rutas ligeras para el feed: como mucho 150 puntos por actividad (uno de cada N), y a los demás
 * sin el tramo dentro de las zonas de privacidad del autor (igual que en el detalle).
 */
async function previewRoutes(db: Db, viewerId: string, acts: { id: string; userId: string }[]) {
  const out = new Map<string, number[][][]>();
  if (!acts.length) return out;
  const tracks = await db.select().from(activityTracks).where(inArray(activityTracks.activityId, acts.map((a) => a.id)));
  const owners = [...new Set(acts.filter((a) => a.userId !== viewerId).map((a) => a.userId))];
  const zones = owners.length
    ? await db.select().from(privacyZones).where(inArray(privacyZones.userId, owners))
    : [];
  const ownerOf = new Map(acts.map((a) => [a.id, a.userId]));
  for (const t of tracks) {
    const points = await decodeTrack(t.data);
    const owner = ownerOf.get(t.activityId)!;
    const mine = zones.filter((z) => z.userId === owner);
    const segments = owner === viewerId ? [points] : applyPrivacyZones(points, mine);
    const total = segments.reduce((n, s) => n + s.length, 0);
    const step = Math.max(1, Math.ceil(total / PREVIEW_POINTS));
    const thin = segments
      .map((seg) => seg.filter((_, i) => i % step === 0 || i === seg.length - 1).map((p) => [round(p[0]), round(p[1])]))
      .filter((seg) => seg.length >= 2);
    if (thin.length) out.set(t.activityId, thin);
  }
  return out;
}

const round = (v: number) => Math.round(v * 1e5) / 1e5;

/** Una línea para avisos: «Aneto», «Tenzing», «Un Everest este año»… */
export async function feedItemLabel(db: Db, item: FeedRow): Promise<string | null> {
  const [hydrated] = await hydrateFeed(db, item.actorId, [item]);
  if (!hydrated) return null;
  if (hydrated.badge) return hydrated.badge.name;
  if (hydrated.challenge) return hydrated.challenge.title;
  const peak = hydrated.ascents?.[0]?.peak;
  if (peak) return peak.nameEs ?? peak.name;
  return hydrated.activity?.title ?? null;
}

export const feedRoutes = new Hono<AppBindings>();
feedRoutes.use("*", requireAuth);

/** Lo mío y lo de mis amigos, de lo más reciente a lo más antiguo. Paginación con `?before=<ms>`. */
feedRoutes.get("/", async (c) => {
  const db = c.var.db;
  const me = c.var.userId;
  const limit = Math.min(Math.max(Number(c.req.query("limit")) || 30, 1), 60);
  const before = Number(c.req.query("before"));
  const actors = [me, ...(await friendIds(db, me))];
  const conditions = [inArray(feedItems.actorId, actors)];
  if (Number.isFinite(before) && before > 0) conditions.push(lt(feedItems.createdAt, new Date(before)));
  const rows = await db
    .select()
    .from(feedItems)
    .where(and(...conditions))
    .orderBy(desc(feedItems.createdAt))
    .limit(limit);
  // Con amigos solo se ve lo que no es privado
  const visible = rows.filter((r) => r.actorId === me || r.visibility !== "private");
  return c.json({
    items: await hydrateFeed(db, me, visible),
    nextBefore: rows.length === limit ? rows[rows.length - 1]!.createdAt.getTime() : null,
  });
});

/** He abierto Amigos: lo anterior deja de contar como novedad. Devuelve las novedades que quedan. */
feedRoutes.post("/seen", async (c) => {
  await c.var.db.update(users).set({ feedSeenAt: new Date() }).where(eq(users.id, c.var.userId));
  return c.json(await badgeCount(c.var.db, c.var.userId));
});

// ---------------------------------------------------------------------------
// Likes y comentarios (sobre elementos del feed)
// ---------------------------------------------------------------------------

export const likesRoutes = new Hono<AppBindings>();
likesRoutes.use("*", requireAuth);

likesRoutes.post("/feed_item/:id", async (c) => {
  const db = c.var.db;
  const item = await visibleFeedItem(db, c.var.userId, c.req.param("id"));
  if (!item) return c.json({ error: "not_found" }, 404);
  const [inserted] = await db
    .insert(likes)
    .values({ userId: c.var.userId, targetType: "feed_item", targetId: item.id })
    .onConflictDoNothing()
    .returning();
  if (inserted) {
    await notify(db, { userId: item.actorId, actorId: c.var.userId, kind: "like", targetType: "feed_item", targetId: item.id });
    if (item.actorId !== c.var.userId) {
      const label = await feedItemLabel(db, item);
      c.var.push.toUser(item.actorId, {
        title: "Sarrio",
        body: `A ${await displayName(db, c.var.userId)} le ha gustado ${label ? `«${label}»` : "tu salida"}`,
        data: { open: "feed" },
      });
    }
  }
  return c.json({ liked: true });
});

likesRoutes.delete("/feed_item/:id", async (c) => {
  await c.var.db
    .delete(likes)
    .where(and(eq(likes.userId, c.var.userId), eq(likes.targetType, "feed_item"), eq(likes.targetId, c.req.param("id"))));
  return c.json({ liked: false });
});

export const commentsRoutes = new Hono<AppBindings>();
commentsRoutes.use("*", requireAuth);

commentsRoutes.get("/feed_item/:id", async (c) => {
  const db = c.var.db;
  const item = await visibleFeedItem(db, c.var.userId, c.req.param("id"));
  if (!item) return c.json({ error: "not_found" }, 404);
  const rows = await db
    .select()
    .from(comments)
    .where(and(eq(comments.targetType, "feed_item"), eq(comments.targetId, item.id)))
    .orderBy(asc(comments.createdAt));
  const people = await publicUsers(db, rows.map((r) => r.userId));
  return c.json({
    comments: rows
      .filter((r) => people.has(r.userId))
      .map((r) => ({ id: r.id, body: r.body, createdAt: r.createdAt.getTime(), author: people.get(r.userId)! })),
  });
});

commentsRoutes.post("/feed_item/:id", async (c) => {
  const db = c.var.db;
  const item = await visibleFeedItem(db, c.var.userId, c.req.param("id"));
  if (!item) return c.json({ error: "not_found" }, 404);
  const body = await c.req.json<Record<string, unknown>>().catch(() => null);
  const text = typeof body?.body === "string" ? body.body.trim() : "";
  if (text.length < 1 || text.length > 500) return c.json({ error: "invalid_comment" }, 400);
  const [row] = await db
    .insert(comments)
    .values({ id: newId(), userId: c.var.userId, targetType: "feed_item", targetId: item.id, body: text })
    .returning();
  await notify(db, { userId: item.actorId, actorId: c.var.userId, kind: "comment", targetType: "feed_item", targetId: item.id });
  if (item.actorId !== c.var.userId) {
    const label = await feedItemLabel(db, item);
    c.var.push.toUser(item.actorId, {
      title: label ? `Comentario en «${label}»` : "Nuevo comentario",
      body: `${await displayName(db, c.var.userId)}: ${text.slice(0, 120)}`,
      data: { open: "feed" },
    });
  }
  const author = (await publicUsers(db, [c.var.userId])).get(c.var.userId)!;
  return c.json({ id: row!.id, body: row!.body, createdAt: row!.createdAt.getTime(), author }, 201);
});

/** Borrar un comentario: quien lo escribió o el dueño de lo comentado. */
commentsRoutes.delete("/:id", async (c) => {
  const db = c.var.db;
  const row = await db.select().from(comments).where(eq(comments.id, c.req.param("id"))).get();
  if (!row) return c.json({ error: "not_found" }, 404);
  let allowed = row.userId === c.var.userId;
  if (!allowed && row.targetType === "feed_item") {
    const item = await db.select({ actorId: feedItems.actorId }).from(feedItems).where(eq(feedItems.id, row.targetId)).get();
    allowed = item?.actorId === c.var.userId;
  }
  if (!allowed) return c.json({ error: "not_found" }, 404);
  await db.delete(comments).where(eq(comments.id, row.id));
  return c.body(null, 204);
});
