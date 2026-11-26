import { sql } from "drizzle-orm";
import {
  blob,
  index,
  integer,
  primaryKey,
  real,
  sqliteTable,
  text,
  uniqueIndex,
} from "drizzle-orm/sqlite-core";

/** Quién puede ver una actividad o ascensión. */
export const visibilityValues = ["private", "friends", "public"] as const;
export type Visibility = (typeof visibilityValues)[number];

/** Fuentes de datos soportadas (o previstas). */
export const sourceValues = ["healthkit", "file", "manual", "polar", "garmin", "suunto", "coros"] as const;
export type Source = (typeof sourceValues)[number];

const id = () => text("id").primaryKey();
const createdAt = () =>
  integer("created_at", { mode: "timestamp_ms" }).notNull().default(sql`(unixepoch() * 1000)`);

// ---------------------------------------------------------------------------
// Usuarios y cuentas
// ---------------------------------------------------------------------------

export const users = sqliteTable(
  "users",
  {
    id: id(),
    appleSub: text("apple_sub").notNull(),
    username: text("username").notNull(),
    displayName: text("display_name").notNull(),
    avatarKey: text("avatar_key"),
    bio: text("bio"),
    defaultVisibility: text("default_visibility", { enum: visibilityValues }).notNull().default("friends"),
    createdAt: createdAt(),
  },
  (t) => [uniqueIndex("users_apple_sub_uq").on(t.appleSub), uniqueIndex("users_username_uq").on(t.username)],
);

/** Conexiones OAuth con proveedores (Polar, Garmin…). Los tokens se guardan cifrados (AES-GCM). */
export const providerConnections = sqliteTable(
  "provider_connections",
  {
    userId: text("user_id").notNull().references(() => users.id, { onDelete: "cascade" }),
    provider: text("provider", { enum: sourceValues }).notNull(),
    externalUserId: text("external_user_id").notNull(),
    accessTokenEnc: text("access_token_enc").notNull(),
    refreshTokenEnc: text("refresh_token_enc"),
    expiresAt: integer("expires_at", { mode: "timestamp_ms" }),
    createdAt: createdAt(),
  },
  (t) => [
    primaryKey({ columns: [t.userId, t.provider] }),
    uniqueIndex("provider_ext_uq").on(t.provider, t.externalUserId),
  ],
);

/** Tokens APNs para notificaciones push. */
export const devices = sqliteTable("devices", {
  token: text("token").primaryKey(),
  userId: text("user_id").notNull().references(() => users.id, { onDelete: "cascade" }),
  environment: text("environment", { enum: ["sandbox", "production"] }).notNull(),
  createdAt: createdAt(),
});

/** Zonas donde se recorta el track antes de enseñarlo a otros (casa, trabajo…). */
export const privacyZones = sqliteTable("privacy_zones", {
  id: id(),
  userId: text("user_id").notNull().references(() => users.id, { onDelete: "cascade" }),
  lat: real("lat").notNull(),
  lon: real("lon").notNull(),
  radiusM: integer("radius_m").notNull().default(500),
});

// ---------------------------------------------------------------------------
// Picos, actividades y ascensiones
// ---------------------------------------------------------------------------

/** Picos de OpenStreetMap (natural=peak). Datos © OpenStreetMap contributors, ODbL. */
export const peaks = sqliteTable(
  "peaks",
  {
    id: integer("id").primaryKey(), // = id del nodo OSM
    name: text("name").notNull(),
    nameEs: text("name_es"),
    ele: real("ele"),
    lat: real("lat").notNull(),
    lon: real("lon").notNull(),
    /** Geohash de 5 caracteres (~4,9 km); los paquetes de picos se sirven por prefijo de 4. */
    geohash: text("geohash").notNull(),
    country: text("country"),
    range: text("range"),
    wikidata: text("wikidata"),
  },
  (t) => [index("peaks_geohash_idx").on(t.geohash), index("peaks_lat_lon_idx").on(t.lat, t.lon)],
);

/** Metadatos del conjunto de picos. `dataset_version` (ms) lo actualiza el workflow de importación. */
export const peakMeta = sqliteTable("peak_meta", {
  key: text("key").primaryKey(),
  value: text("value").notNull(),
});

export const activities = sqliteTable(
  "activities",
  {
    id: id(),
    userId: text("user_id").notNull().references(() => users.id, { onDelete: "cascade" }),
    source: text("source", { enum: sourceValues }).notNull(),
    /** Identificador en la fuente (UUID de HealthKit, id de Polar, hash del archivo…), para deduplicar. */
    externalId: text("external_id").notNull(),
    sportType: text("sport_type").notNull(),
    title: text("title"),
    startAt: integer("start_at", { mode: "timestamp_ms" }).notNull(),
    durationS: integer("duration_s"),
    distanceM: real("distance_m"),
    elevGainM: real("elev_gain_m"),
    minLat: real("min_lat"),
    minLon: real("min_lon"),
    maxLat: real("max_lat"),
    maxLon: real("max_lon"),
    /** Sin uso: la ruta vive en `activity_tracks` (comprimida en la propia base de datos, sin R2). */
    trackKey: text("track_key"),
    visibility: text("visibility", { enum: visibilityValues }).notNull().default("friends"),
    createdAt: createdAt(),
  },
  (t) => [
    uniqueIndex("activities_source_uq").on(t.userId, t.source, t.externalId),
    index("activities_user_start_idx").on(t.userId, t.startAt),
  ],
);

/**
 * Ruta de una actividad, comprimida (gzip de JSON) en la propia base de datos.
 * Formato `gz-json-v1`: `[[lat, lon, ele | null, t | null], …]`, con `t` en segundos desde `start_at`.
 * El cliente la simplifica antes de subirla (Douglas-Peucker), así que ocupa pocos KB.
 */
export const activityTracks = sqliteTable("activity_tracks", {
  activityId: text("activity_id").primaryKey().references(() => activities.id, { onDelete: "cascade" }),
  encoding: text("encoding").notNull().default("gz-json-v1"),
  pointCount: integer("point_count").notNull(),
  data: blob("data", { mode: "buffer" }).notNull(),
});

export const ascents = sqliteTable(
  "ascents",
  {
    id: id(),
    userId: text("user_id").notNull().references(() => users.id, { onDelete: "cascade" }),
    peakId: integer("peak_id").notNull().references(() => peaks.id),
    activityId: text("activity_id").references(() => activities.id, { onDelete: "set null" }),
    summitedAt: integer("summited_at", { mode: "timestamp_ms" }).notNull(),
    note: text("note"),
    visibility: text("visibility", { enum: visibilityValues }).notNull().default("friends"),
    createdAt: createdAt(),
  },
  (t) => [
    uniqueIndex("ascents_activity_peak_uq").on(t.activityId, t.peakId),
    index("ascents_user_idx").on(t.userId, t.summitedAt),
    index("ascents_peak_idx").on(t.peakId),
  ],
);

// ---------------------------------------------------------------------------
// Emblemas y retos
// ---------------------------------------------------------------------------

export const badges = sqliteTable("badges", {
  id: text("id").primaryKey(), // slug, p. ej. "first-summit"
  name: text("name").notNull(),
  description: text("description").notNull(),
  icon: text("icon").notNull(), // nombre del asset en la app (Badges.xcassets)
  tier: text("tier", { enum: ["bronze", "silver", "gold", "special", "legend"] }).notNull(),
  category: text("category").notNull().default(""),
  sortOrder: integer("sort_order").notNull().default(0),
});

export const userBadges = sqliteTable(
  "user_badges",
  {
    userId: text("user_id").notNull().references(() => users.id, { onDelete: "cascade" }),
    badgeId: text("badge_id").notNull().references(() => badges.id),
    ascentId: text("ascent_id").references(() => ascents.id, { onDelete: "set null" }),
    activityId: text("activity_id").references(() => activities.id, { onDelete: "set null" }),
    earnedAt: integer("earned_at", { mode: "timestamp_ms" }).notNull(),
  },
  (t) => [primaryKey({ columns: [t.userId, t.badgeId] })],
);

export const challengeKindValues = ["metric", "peaks"] as const;
export const challengeMetricValues = [
  "elevation_gain",
  "distance",
  "summits",
  "unique_peaks",
  "activities",
  "active_weeks",
  "high_summits",
  "sunrise_summits",
  "max_activity_gain",
] as const;
export type ChallengeMetric = (typeof challengeMetricValues)[number];
export const recurrenceValues = ["none", "monthly", "yearly"] as const;

export const challenges = sqliteTable(
  "challenges",
  {
    id: id(),
    /** null = reto oficial de Sarrio. */
    creatorId: text("creator_id").references(() => users.id, { onDelete: "cascade" }),
    /** Identificador estable de los retos oficiales (siembra idempotente). */
    slug: text("slug"),
    title: text("title").notNull(),
    description: text("description"),
    visibility: text("visibility", { enum: visibilityValues }).notNull().default("public"),
    kind: text("kind", { enum: challengeKindValues }).notNull().default("metric"),
    metric: text("metric", { enum: challengeMetricValues }),
    target: real("target"),
    /** Solo actividades de este deporte (p. ej. trail_running). */
    sport: text("sport"),
    /** Altitud mínima para `high_summits`. */
    minEle: real("min_ele"),
    recurrence: text("recurrence", { enum: recurrenceValues }).notNull().default("none"),
    /** Ventana dentro del año, "MM-DD..MM-DD" (puede cruzar el año: "12-21..03-20"). */
    window: text("window"),
    sortOrder: integer("sort_order").notNull().default(0),
    /** Reto de Leyenda: al completarlo se gana este emblema (aunque no te hayas unido). */
    badgeId: text("badge_id").references(() => badges.id),
    startsAt: integer("starts_at", { mode: "timestamp_ms" }),
    endsAt: integer("ends_at", { mode: "timestamp_ms" }),
    createdAt: createdAt(),
  },
  (t) => [uniqueIndex("challenges_slug_uq").on(t.slug), index("challenges_creator_idx").on(t.creatorId)],
);

export const challengePeaks = sqliteTable(
  "challenge_peaks",
  {
    challengeId: text("challenge_id").notNull().references(() => challenges.id, { onDelete: "cascade" }),
    peakId: integer("peak_id").notNull().references(() => peaks.id),
  },
  (t) => [primaryKey({ columns: [t.challengeId, t.peakId] })],
);

export const challengeParticipants = sqliteTable(
  "challenge_participants",
  {
    challengeId: text("challenge_id").notNull().references(() => challenges.id, { onDelete: "cascade" }),
    userId: text("user_id").notNull().references(() => users.id, { onDelete: "cascade" }),
    joinedAt: createdAt(),
    completedAt: integer("completed_at", { mode: "timestamp_ms" }),
  },
  (t) => [primaryKey({ columns: [t.challengeId, t.userId] })],
);

// ---------------------------------------------------------------------------
// Social
// ---------------------------------------------------------------------------

export const friendships = sqliteTable(
  "friendships",
  {
    requesterId: text("requester_id").notNull().references(() => users.id, { onDelete: "cascade" }),
    addresseeId: text("addressee_id").notNull().references(() => users.id, { onDelete: "cascade" }),
    status: text("status", { enum: ["pending", "accepted"] }).notNull().default("pending"),
    createdAt: createdAt(),
    respondedAt: integer("responded_at", { mode: "timestamp_ms" }),
  },
  (t) => [
    primaryKey({ columns: [t.requesterId, t.addresseeId] }),
    index("friendships_addressee_idx").on(t.addresseeId, t.status),
  ],
);

export const blocks = sqliteTable(
  "blocks",
  {
    blockerId: text("blocker_id").notNull().references(() => users.id, { onDelete: "cascade" }),
    blockedId: text("blocked_id").notNull().references(() => users.id, { onDelete: "cascade" }),
    createdAt: createdAt(),
  },
  (t) => [primaryKey({ columns: [t.blockerId, t.blockedId] })],
);

export const targetTypeValues = ["ascent", "activity", "user_badge", "challenge"] as const;

export const likes = sqliteTable(
  "likes",
  {
    userId: text("user_id").notNull().references(() => users.id, { onDelete: "cascade" }),
    targetType: text("target_type", { enum: targetTypeValues }).notNull(),
    targetId: text("target_id").notNull(),
    createdAt: createdAt(),
  },
  (t) => [
    primaryKey({ columns: [t.userId, t.targetType, t.targetId] }),
    index("likes_target_idx").on(t.targetType, t.targetId),
  ],
);

export const comments = sqliteTable(
  "comments",
  {
    id: id(),
    userId: text("user_id").notNull().references(() => users.id, { onDelete: "cascade" }),
    targetType: text("target_type", { enum: targetTypeValues }).notNull(),
    targetId: text("target_id").notNull(),
    body: text("body").notNull(),
    createdAt: createdAt(),
  },
  (t) => [index("comments_target_idx").on(t.targetType, t.targetId, t.createdAt)],
);

export const reports = sqliteTable("reports", {
  id: id(),
  reporterId: text("reporter_id").notNull().references(() => users.id, { onDelete: "cascade" }),
  targetType: text("target_type", { enum: [...targetTypeValues, "comment", "user"] }).notNull(),
  targetId: text("target_id").notNull(),
  reason: text("reason").notNull(),
  createdAt: createdAt(),
  resolvedAt: integer("resolved_at", { mode: "timestamp_ms" }),
});

/** Eventos del feed (fan-out en lectura: se consultan los de mis amigos). */
export const feedItems = sqliteTable(
  "feed_items",
  {
    id: id(),
    actorId: text("actor_id").notNull().references(() => users.id, { onDelete: "cascade" }),
    kind: text("kind", { enum: ["ascent", "badge", "challenge_completed"] }).notNull(),
    refId: text("ref_id").notNull(),
    visibility: text("visibility", { enum: visibilityValues }).notNull(),
    createdAt: createdAt(),
  },
  (t) => [index("feed_actor_idx").on(t.actorId, t.createdAt)],
);

export const notifications = sqliteTable(
  "notifications",
  {
    id: id(),
    userId: text("user_id").notNull().references(() => users.id, { onDelete: "cascade" }),
    actorId: text("actor_id").references(() => users.id, { onDelete: "cascade" }),
    kind: text("kind", {
      enum: ["friend_request", "friend_accepted", "like", "comment", "challenge_invite", "badge"],
    }).notNull(),
    targetType: text("target_type"),
    targetId: text("target_id"),
    readAt: integer("read_at", { mode: "timestamp_ms" }),
    createdAt: createdAt(),
  },
  (t) => [index("notifications_user_idx").on(t.userId, t.createdAt)],
);
