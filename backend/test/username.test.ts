import { describe, expect, it } from "vitest";
import { createTestApp } from "./helpers";

describe("choosing the username", () => {
  it("checks availability, lets me choose once and then locks it", async () => {
    const { request, signIn } = await createTestApp();
    await signIn("001", "Ana");
    const { token } = await signIn("002", "Bea");
    const check = async (u: string) => (await (await request("GET", `/v1/users/available?username=${u}`, { token })).json()) as any;

    expect(await check("ana")).toMatchObject({ available: false, reason: "taken" });
    expect(await check("a")).toMatchObject({ available: false, reason: "invalid" });
    expect(await check("Sarrio")).toMatchObject({ username: "sarrio", available: false, reason: "reserved" });
    expect(await check("bea.pirineo")).toMatchObject({ available: true, reason: null });

    expect((await request("POST", "/v1/me/username", { token, body: { username: "ana" } })).status).toBe(409);
    expect((await request("POST", "/v1/me/username", { token, body: { username: "admin" } })).status).toBe(400);
    const ok = await request("POST", "/v1/me/username", { token, body: { username: "bea.pirineo" } });
    expect(ok.status).toBe(200);
    expect(((await ok.json()) as any).usernameLocked).toBe(true);

    const again = await request("POST", "/v1/me/username", { token, body: { username: "bea.otra" } });
    expect(again.status).toBe(409);
    expect(((await again.json()) as any).error).toBe("username_locked");
    expect((await request("PATCH", "/v1/me", { token, body: { username: "bea.otra" } })).status).toBe(400);
    // El mismo usuario (versiones antiguas de la app lo mandan siempre) se acepta
    expect((await request("PATCH", "/v1/me", { token, body: { username: "bea.pirineo", bio: "Hola" } })).status).toBe(200);
  });
});
