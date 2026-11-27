import { Hono } from "hono";
import { logger } from "hono/logger";
import type { AppBindings, Deps } from "./env";
import { getDb } from "./db/client";
import { createPusher } from "./services/push";
import { verifyAppleIdentityToken } from "./auth/apple";
import { activitiesRoutes } from "./routes/activities";
import { ascentsRoutes } from "./routes/ascents";
import { authRoutes } from "./routes/auth";
import { avatarsRoutes } from "./routes/avatars";
import { badgesRoutes } from "./routes/badges";
import { challengesRoutes } from "./routes/challenges";
import { commentsRoutes, feedRoutes, likesRoutes } from "./routes/feed";
import { blocksRoutes, friendsRoutes, reportsRoutes } from "./routes/friends";
import { notificationsRoutes } from "./routes/notifications";
import { meRoutes } from "./routes/me";
import { peaksRoutes } from "./routes/peaks";
import { providersRoutes } from "./routes/providers";
import { usersRoutes } from "./routes/users";

export const defaultDeps: Deps = { getDb, verifyAppleToken: verifyAppleIdentityToken };

export function createApp(deps: Deps = defaultDeps) {
  const app = new Hono<AppBindings>();

  app.use("*", logger());
  app.use("*", async (c, next) => {
    c.set("deps", deps);
    c.set("db", deps.getDb(c.env));
    // Notificaciones push: se envían sin hacer esperar la respuesta (en tests no hay executionCtx)
    const waitUntil = (p: Promise<unknown>) => {
      try {
        c.executionCtx.waitUntil(p);
      } catch {
        void p;
      }
    };
    c.set("push", createPusher(c.env, c.var.db, deps.fetch ?? fetch, waitUntil));
    await next();
  });

  app.get("/health", (c) => c.json({ ok: true, service: "sarrio-api" }));

  const v1 = new Hono<AppBindings>();
  v1.route("/auth", authRoutes);
  v1.route("/me", meRoutes);
  v1.route("/users", usersRoutes);
  v1.route("/peaks", peaksRoutes);
  v1.route("/activities", activitiesRoutes);
  v1.route("/ascents", ascentsRoutes);
  v1.route("/providers", providersRoutes);
  v1.route("/badges", badgesRoutes);
  v1.route("/challenges", challengesRoutes);
  v1.route("/friends", friendsRoutes);
  v1.route("/blocks", blocksRoutes);
  v1.route("/reports", reportsRoutes);
  v1.route("/feed", feedRoutes);
  v1.route("/likes", likesRoutes);
  v1.route("/comments", commentsRoutes);
  v1.route("/notifications", notificationsRoutes);
  app.route("/v1", v1);
  app.route("/avatars", avatarsRoutes);

  app.notFound((c) => c.json({ error: "not_found" }, 404));
  app.onError((err, c) => {
    console.error(err);
    return c.json({ error: "internal_error" }, 500);
  });
  return app;
}
