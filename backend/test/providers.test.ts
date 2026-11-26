import { describe, expect, it } from "vitest";
import { createTestApp } from "./helpers";
import { providerConnections } from "../src/db/schema";
import { decryptToken, encryptToken } from "../src/lib/crypto";
import { isoDurationSeconds } from "../src/services/polar";

const POLAR_ENV = { POLAR_CLIENT_ID: "client-1", POLAR_CLIENT_SECRET: "secret-1" };
const KEY = "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=";

/** Polar falso: guarda las llamadas y responde como AccessLink. */
function fakePolar(overrides: { exercisesStatus?: number } = {}) {
  const calls: { url: string; method: string; headers: Record<string, string>; body?: string }[] = [];
  const fake: typeof fetch = async (input, init) => {
    const url = String(input);
    const headers = Object.fromEntries(new Headers(init?.headers).entries());
    calls.push({ url, method: init?.method ?? "GET", headers, body: init?.body?.toString() });
    if (url.startsWith("https://polarremote.com/v2/oauth2/token")) {
      return Response.json({ access_token: "polar-token", token_type: "bearer", x_user_id: 4242 });
    }
    if (url === "https://www.polaraccesslink.com/v3/users") return new Response(null, { status: 409 });
    if (url === "https://www.polaraccesslink.com/v3/exercises") {
      if (overrides.exercisesStatus) return new Response(null, { status: overrides.exercisesStatus });
      return Response.json([
        { id: "ex1", start_time: "2026-07-14T07:00:00", start_time_utc_offset: 120, duration: "PT5H3M2.5S", distance: 14800, sport: "HIKING", has_route: true },
        { id: "ex2", start_time: "2026-07-20T18:00:00", duration: "PT45M", sport: "RUNNING", has_route: false },
      ]);
    }
    if (url === "https://www.polaraccesslink.com/v3/exercises/ex1/fit") return new Response(new Uint8Array([14, 16, 1, 2]));
    if (url.startsWith("https://www.polaraccesslink.com/v3/users/")) return new Response(null, { status: 204 });
    return new Response("not found", { status: 404 });
  };
  return { fake, calls };
}

async function connect(t: Awaited<ReturnType<typeof createTestApp>>, token: string) {
  const { url } = (await (await t.request("POST", "/v1/providers/polar/connect", { token })).json()) as { url: string };
  const state = new URL(url).searchParams.get("state")!;
  return t.app.request(`/v1/providers/polar/callback?code=abc&state=${encodeURIComponent(state)}`, {}, { ...(await import("./helpers")).testEnv, ...POLAR_ENV } as any);
}

describe("crypto", () => {
  it("round-trips provider tokens with AES-GCM", async () => {
    const stored = await encryptToken("polar-token", KEY);
    expect(stored).not.toContain("polar-token");
    expect(await decryptToken(stored, KEY)).toBe("polar-token");
  });
  it("parses ISO durations", () => {
    expect(isoDurationSeconds("PT5H3M2.5S")).toBe(5 * 3600 + 3 * 60 + 2.5);
    expect(isoDurationSeconds("PT45M")).toBe(2700);
    expect(isoDurationSeconds("nope")).toBeNull();
  });
});

describe("Polar", () => {
  it("reports when Polar is not configured", async () => {
    const t = await createTestApp();
    const { token } = await t.signIn("ana", "Ana");
    expect((await t.request("POST", "/v1/providers/polar/connect", { token })).status).toBe(503);
    const status = (await (await t.request("GET", "/v1/providers", { token })).json()) as any;
    expect(status.providers[0]).toEqual({ provider: "polar", configured: false, connected: false });
  });

  it("connects through OAuth, stores the token encrypted and redirects to the app", async () => {
    const polar = fakePolar();
    const t = await createTestApp({ fetch: polar.fake, env: POLAR_ENV });
    const { token, user } = await t.signIn("ana", "Ana");

    const { url } = (await (await t.request("POST", "/v1/providers/polar/connect", { token })).json()) as { url: string };
    const auth = new URL(url);
    expect(auth.origin + auth.pathname).toBe("https://flow.polar.com/oauth2/authorization");
    expect(auth.searchParams.get("client_id")).toBe("client-1");
    expect(auth.searchParams.get("redirect_uri")).toBe("http://localhost/v1/providers/polar/callback");

    const res = await t.request("GET", `/v1/providers/polar/callback?code=abc&state=${encodeURIComponent(auth.searchParams.get("state")!)}`);
    expect(res.status).toBe(302);
    expect(res.headers.get("location")).toBe("sarrio://polar?status=connected");

    const tokenCall = polar.calls.find((c) => c.url.includes("oauth2/token"))!;
    expect(tokenCall.headers.authorization).toBe(`Basic ${btoa("client-1:secret-1")}`);
    expect(tokenCall.body).toContain("code=abc");
    const register = polar.calls.find((c) => c.url.endsWith("/v3/users"))!;
    expect(JSON.parse(register.body!)).toEqual({ "member-id": user.id });

    const [row] = await t.db.select().from(providerConnections);
    expect(row!.externalUserId).toBe("4242");
    expect(row!.accessTokenEnc).not.toContain("polar-token");

    const status = (await (await t.request("GET", "/v1/providers", { token })).json()) as any;
    expect(status.providers[0].connected).toBe(true);
  });

  it("rejects forged state and passes cancellations back to the app", async () => {
    const t = await createTestApp({ fetch: fakePolar().fake, env: POLAR_ENV });
    const forged = await t.request("GET", "/v1/providers/polar/callback?code=abc&state=forged");
    expect(forged.headers.get("location")).toBe("sarrio://polar?status=error&reason=invalid_state");
    const cancelled = await t.request("GET", "/v1/providers/polar/callback?error=access_denied");
    expect(cancelled.headers.get("location")).toBe("sarrio://polar?status=cancelled&reason=access_denied");
  });

  it("lists exercises, marks the imported ones and proxies the FIT", async () => {
    const polar = fakePolar();
    const t = await createTestApp({ fetch: polar.fake, env: POLAR_ENV });
    const { token } = await t.signIn("ana", "Ana");
    expect((await t.request("GET", "/v1/providers/polar/exercises", { token })).status).toBe(409);
    expect((await t.request("POST", "/v1/activities", {
      token,
      body: { source: "polar", externalId: "ex1", sportType: "hiking", startAt: 1, track: [] },
    })).status).toBe(409);

    await connect(t, token);
    await t.request("POST", "/v1/activities", {
      token,
      body: { source: "polar", externalId: "ex1", sportType: "hiking", startAt: 1, track: [] },
    });

    const list = (await (await t.request("GET", "/v1/providers/polar/exercises", { token })).json()) as any;
    expect(list.exercises).toHaveLength(2);
    expect(list.exercises[0]).toMatchObject({ id: "ex1", durationS: 18182.5, hasRoute: true, imported: true, sport: "HIKING" });
    expect(list.exercises[1]).toMatchObject({ id: "ex2", hasRoute: false, imported: false });
    expect(polar.calls.find((c) => c.url.endsWith("/v3/exercises"))!.headers.authorization).toBe("Bearer polar-token");

    const fit = await t.request("GET", "/v1/providers/polar/exercises/ex1/fit", { token });
    expect(fit.status).toBe(200);
    expect(new Uint8Array(await fit.arrayBuffer())).toEqual(new Uint8Array([14, 16, 1, 2]));
    expect((await t.request("GET", "/v1/providers/polar/exercises/..%2F/fit", { token })).status).toBe(400);
  });

  it("forgets the connection when Polar says the access was revoked", async () => {
    const t = await createTestApp({ fetch: fakePolar({ exercisesStatus: 401 }).fake, env: POLAR_ENV });
    const { token } = await t.signIn("ana", "Ana");
    await connect(t, token);
    const res = await t.request("GET", "/v1/providers/polar/exercises", { token });
    expect(res.status).toBe(409);
    expect(((await res.json()) as any).error).toBe("polar_revoked");
    expect(await t.db.select().from(providerConnections)).toHaveLength(0);
  });

  it("disconnects and deregisters the user", async () => {
    const polar = fakePolar();
    const t = await createTestApp({ fetch: polar.fake, env: POLAR_ENV });
    const { token } = await t.signIn("ana", "Ana");
    await connect(t, token);
    expect((await t.request("DELETE", "/v1/providers/polar", { token })).status).toBe(204);
    expect(polar.calls.some((c) => c.method === "DELETE" && c.url.endsWith("/v3/users/4242"))).toBe(true);
    expect(await t.db.select().from(providerConnections)).toHaveLength(0);
  });
});
