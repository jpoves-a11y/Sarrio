import { describe, expect, it } from "vitest";
import { canView } from "../src/services/visibility";

describe("canView", () => {
  it("lets the author see everything", () => {
    for (const v of ["private", "friends", "public"] as const) expect(canView(v, "self")).toBe(true);
  });
  it("lets friends see friends and public content", () => {
    expect(canView("private", "friend")).toBe(false);
    expect(canView("friends", "friend")).toBe(true);
    expect(canView("public", "friend")).toBe(true);
  });
  it("lets strangers see only public content", () => {
    expect(canView("friends", "stranger")).toBe(false);
    expect(canView("public", "stranger")).toBe(true);
  });
  it("hides everything from blocked users", () => {
    expect(canView("public", "blocked")).toBe(false);
  });
});
