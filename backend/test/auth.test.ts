import { describe, expect, it } from "vitest";
import { createTestApp } from "./helpers";
import { isValidUsername, usernameSeed } from "../src/lib/validation";
import { sha256Hex } from "../src/auth/apple";

describe("POST /v1/auth/apple", () => {
  it("creates the user on first sign in and reuses it afterwards", async () => {
    const { request } = await createTestApp();
    const first = await request("POST", "/v1/auth/apple", { body: { identityToken: "apple:001", fullName: "Lucía Peña" } });
    expect(first.status).toBe(201);
    const a = (await first.json()) as any;
    expect(a.isNew).toBe(true);
    expect(a.user.username).toBe("luciapena");
    expect(a.user.displayName).toBe("Lucía Peña");
    expect(a.token).toBeTypeOf("string");

    const second = await request("POST", "/v1/auth/apple", { body: { identityToken: "apple:001" } });
    expect(second.status).toBe(200);
    const b = (await second.json()) as any;
    expect(b.isNew).toBe(false);
    expect(b.user.id).toBe(a.user.id);
  });

  it("generates a different username when the seed is taken", async () => {
    const { signIn } = await createTestApp();
    const a = await signIn("001", "Ana");
    const b = await signIn("002", "Ana");
    expect(a.user.username).toBe("ana");
    expect(b.user.username).not.toBe("ana");
    expect(b.user.username.startsWith("ana")).toBe(true);
  });

  it("rejects invalid identity tokens", async () => {
    const { request } = await createTestApp();
    expect((await request("POST", "/v1/auth/apple", { body: { identityToken: "forged" } })).status).toBe(401);
    expect((await request("POST", "/v1/auth/apple", { body: {} })).status).toBe(400);
  });
});

describe("/v1/me", () => {
  it("requires a valid session", async () => {
    const { request } = await createTestApp();
    expect((await request("GET", "/v1/me")).status).toBe(401);
    expect((await request("GET", "/v1/me", { token: "nope" })).status).toBe(401);
  });

  it("returns and updates the profile", async () => {
    const { request, signIn } = await createTestApp();
    const { token } = await signIn("001", "Lucía");
    const res = await request("PATCH", "/v1/me", {
      token,
      body: { bio: "  Tresmiles  ", defaultVisibility: "public" },
    });
    expect(res.status).toBe(200);
    const me = (await res.json()) as any;
    expect(me).toMatchObject({ bio: "Tresmiles", defaultVisibility: "public", usernameLocked: false });
    // El usuario se elige una vez
    const chosen = await request("POST", "/v1/me/username", { token, body: { username: "Lucia.Pirineo" } });
    expect(((await chosen.json()) as any)).toMatchObject({ username: "lucia.pirineo", usernameLocked: true });
    expect(((await (await request("GET", "/v1/me", { token })).json()) as any).username).toBe("lucia.pirineo");
  });

  it("validates fields and username uniqueness", async () => {
    const { request, signIn } = await createTestApp();
    await signIn("001", "Ana");
    const { token } = await signIn("002", "Bea");
    expect((await request("PATCH", "/v1/me", { token, body: { username: "otra" } })).status).toBe(400);
    expect((await request("PATCH", "/v1/me", { token, body: { defaultVisibility: "everyone" } })).status).toBe(400);
    expect((await request("PATCH", "/v1/me", { token, body: { displayName: "" } })).status).toBe(400);
  });

  it("deletes the account", async () => {
    const { request, signIn } = await createTestApp();
    const { token, user } = await signIn("001", "Ana");
    expect((await request("DELETE", "/v1/me", { token })).status).toBe(204);
    expect((await request("GET", "/v1/me", { token })).status).toBe(404);
    // Volver a entrar crea una cuenta nueva.
    const again = await signIn("001");
    expect(again.isNew).toBe(true);
    expect(again.user.id).not.toBe(user.id);
  });
});

describe("/v1/users/:username", () => {
  it("returns the public profile without private fields", async () => {
    const { request, signIn } = await createTestApp();
    await signIn("001", "Ana");
    const { token } = await signIn("002", "Bea");
    const res = await request("GET", "/v1/users/ANA", { token });
    expect(res.status).toBe(200);
    const body = (await res.json()) as any;
    expect(body.username).toBe("ana");
    expect(body.defaultVisibility).toBeUndefined();
    expect((await request("GET", "/v1/users/nadie", { token })).status).toBe(404);
  });
});

describe("validation helpers", () => {
  it("checks usernames", () => {
    expect(isValidUsername("lucia_88")).toBe(true);
    expect(isValidUsername("ab")).toBe(false);
    expect(isValidUsername("_lucia")).toBe(false);
    expect(isValidUsername("lu..cia")).toBe(false);
  });
  it("builds a username seed without accents", () => {
    expect(usernameSeed("José Ñúñez")).toBe("josenunez");
    expect(usernameSeed(null)).toBe("montanero");
  });
  it("hashes the nonce like Apple expects", async () => {
    expect(await sha256Hex("abc")).toBe("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
  });
});
