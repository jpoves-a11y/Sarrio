import { Hono } from "hono";
import { logger } from "hono/logger";
import type { AppBindings } from "./env";
import { peaksRoutes } from "./routes/peaks";

export const app = new Hono<AppBindings>();

app.use("*", logger());

app.get("/health", (c) => c.json({ ok: true, service: "sarrio-api" }));

const v1 = new Hono<AppBindings>();
v1.route("/peaks", peaksRoutes);
// Fase 2: v1.route("/auth", authRoutes)  — Sign in with Apple → JWT
// Fase 3: v1.route("/activities", …), v1.route("/ascents", …)
// Fase 6: v1.route("/friends", …), v1.route("/feed", …), likes/comments
// Fase 7: v1.route("/providers/polar", …) — OAuth + webhook
app.route("/v1", v1);

app.notFound((c) => c.json({ error: "not_found" }, 404));
app.onError((err, c) => {
  console.error(err);
  return c.json({ error: "internal_error" }, 500);
});
