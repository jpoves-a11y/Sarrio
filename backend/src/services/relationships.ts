import { and, eq, or } from "drizzle-orm";
import type { Db } from "../db/client";
import { blocks, friendships } from "../db/schema";
import type { Relationship } from "./visibility";

/** Relación entre quien mira (`viewerId`) y el autor del contenido (`ownerId`). */
export async function getRelationship(db: Db, viewerId: string, ownerId: string): Promise<Relationship> {
  if (viewerId === ownerId) return "self";

  const block = await db
    .select({ id: blocks.blockerId })
    .from(blocks)
    .where(
      or(
        and(eq(blocks.blockerId, viewerId), eq(blocks.blockedId, ownerId)),
        and(eq(blocks.blockerId, ownerId), eq(blocks.blockedId, viewerId)),
      ),
    )
    .get();
  if (block) return "blocked";

  const friendship = await db
    .select({ status: friendships.status })
    .from(friendships)
    .where(
      and(
        eq(friendships.status, "accepted"),
        or(
          and(eq(friendships.requesterId, viewerId), eq(friendships.addresseeId, ownerId)),
          and(eq(friendships.requesterId, ownerId), eq(friendships.addresseeId, viewerId)),
        ),
      ),
    )
    .get();
  return friendship ? "friend" : "stranger";
}
