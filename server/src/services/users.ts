import { eq } from 'drizzle-orm'
import { db } from '../db/index.js'
import { users } from '../db/schema.js'

export interface AppUser {
  id: string
  clerkId: string
}

/** Look up (or create) the internal user row for a Clerk user id. */
export async function upsertUser(clerkId: string, email?: string | null): Promise<AppUser> {
  const [row] = await db
    .insert(users)
    .values({ clerkId, email: email ?? null })
    .onConflictDoUpdate({ target: users.clerkId, set: { email: email ?? null } })
    .returning({ id: users.id, clerkId: users.clerkId })
  return row!
}

export async function getUserByClerkId(clerkId: string): Promise<AppUser | undefined> {
  const [row] = await db
    .select({ id: users.id, clerkId: users.clerkId })
    .from(users)
    .where(eq(users.clerkId, clerkId))
    .limit(1)
  return row
}
