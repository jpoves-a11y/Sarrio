import { visibilityValues, type Visibility } from "../db/schema";

export const USERNAME_RE = /^[a-z0-9](?:[a-z0-9._]{1,18}[a-z0-9])$/;

export function normalizeUsername(raw: string): string {
  return raw.trim().toLowerCase();
}

export function isValidUsername(u: string): boolean {
  return USERNAME_RE.test(u) && !u.includes("..");
}

export function isVisibility(v: unknown): v is Visibility {
  return typeof v === "string" && (visibilityValues as readonly string[]).includes(v);
}

/** Propuesta de username a partir del nombre de Apple (sin acentos ni espacios). */
export function usernameSeed(name?: string | null): string {
  const base = (name ?? "")
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "")
    .slice(0, 14);
  return base.length >= 3 ? base : "montanero";
}
