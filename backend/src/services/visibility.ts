import type { Visibility } from "../db/schema";

export type Relationship = "self" | "friend" | "stranger" | "blocked";

/** Regla única de visibilidad para ascensiones, actividades, retos y elementos del feed. */
export function canView(visibility: Visibility, relationship: Relationship): boolean {
  switch (relationship) {
    case "self":
      return true;
    case "blocked":
      return false;
    case "friend":
      return visibility === "friends" || visibility === "public";
    case "stranger":
      return visibility === "public";
  }
}

/** Los demás nunca ven el track exacto dentro de las zonas de privacidad; el propio autor sí. */
export function mustTrimTrack(relationship: Relationship): boolean {
  return relationship !== "self";
}
