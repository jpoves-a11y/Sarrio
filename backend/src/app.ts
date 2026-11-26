import { Hono } from "hono";
import { logger } from "hono/logger";
import type { AppBindings, Deps } from "./env";
import { getDb } from "./db/client";
import { verifyAppleIdentityToken } from "./auth/apple";
import { activitiesRoutes } from "./routes/activities";
import { ascentsRoutes } from "./routes/ascents";
import { authRoutes } from "./routes/auth";
import { badgesRoutes } from "./routes/badges";
import { challengesRoutes } from "./routes/challenges";
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
  // Fase 6: /friends, /feed, likes, comments
  app.route("/v1", v1);

  app.notFound((c) => c.json({ error: "not_found" }, 404));
  app.onError((err, c) => {
    console.error(err);
    return c.json({ error: "internal_error" }, 500);
  });
  return app;
}
