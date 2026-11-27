import { describe, expect, it } from "vitest";
import { createTestApp, testEnv } from "./helpers";

const jpeg = (size = 2000) => {
  const b = new Uint8Array(size);
  b.set([0xff, 0xd8, 0xff, 0xe0]);
  b[size - 2] = 0xff;
  b[size - 1] = 0xd9;
  return b;
};

describe("profile photo and city", () => {
  it("uploads, serves, replaces and removes the photo", async () => {
    const t = await createTestApp();
    const ana = await t.signIn("ana", "Ana");
    const bea = await t.signIn("bea", "Bea");
    const put = (body: Uint8Array) =>
      t.app.request("/v1/me/avatar", { method: "PUT", headers: { Authorization: `Bearer ${ana.token}`, "Content-Type": "image/jpeg" }, body }, testEnv);

    expect((await put(new Uint8Array([1, 2, 3, 4]))).status).toBe(400);
    expect((await put(jpeg(400 * 1024))).status).toBe(400);

    const first = (await (await put(jpeg())).json()) as { avatarKey: string };
    expect(first.avatarKey).toBeTruthy();
    const photo = await t.app.request(`/avatars/${ana.user.id}/${first.avatarKey}.jpg`, {}, testEnv);
    expect(photo.status).toBe(200);
    expect(photo.headers.get("content-type")).toBe("image/jpeg");
    expect(photo.headers.get("cache-control")).toContain("immutable");
    expect((await photo.arrayBuffer()).byteLength).toBe(2000);

    // Los demás la ven con su clave
    const seen = (await (await t.request("GET", `/v1/users/${ana.user.username}`, { token: bea.token })).json()) as any;
    expect(seen.avatarKey).toBe(first.avatarKey);

    const second = (await (await put(jpeg(3000))).json()) as { avatarKey: string };
    expect(second.avatarKey).not.toBe(first.avatarKey);
    expect((await t.app.request(`/avatars/${ana.user.id}/${first.avatarKey}.jpg`, {}, testEnv)).status).toBe(404);

    expect((await t.request("DELETE", "/v1/me/avatar", { token: ana.token })).status).toBe(200);
    expect((await t.app.request(`/avatars/${ana.user.id}/${second.avatarKey}.jpg`, {}, testEnv)).status).toBe(404);
    const me = (await (await t.request("GET", "/v1/me", { token: ana.token })).json()) as any;
    expect(me.avatarKey).toBeNull();
  });

  it("saves, shows and clears the city", async () => {
    const t = await createTestApp();
    const ana = await t.signIn("ana", "Ana");
    const bea = await t.signIn("bea", "Bea");
    const res = await t.request("PATCH", "/v1/me", { token: ana.token, body: { city: "  Jaca, Huesca " } });
    expect(((await res.json()) as any).city).toBe("Jaca, Huesca");
    expect((await t.request("PATCH", "/v1/me", { token: ana.token, body: { city: "x".repeat(61) } })).status).toBe(400);

    const found = (await (await t.request("GET", "/v1/users/search?q=ana", { token: bea.token })).json()) as any;
    expect(found.users[0].city).toBe("Jaca, Huesca");
    const profile = (await (await t.request("GET", `/v1/users/${ana.user.username}`, { token: bea.token })).json()) as any;
    expect(profile.city).toBe("Jaca, Huesca");

    const cleared = await t.request("PATCH", "/v1/me", { token: ana.token, body: { city: "" } });
    expect(((await cleared.json()) as any).city).toBeNull();
  });
});
