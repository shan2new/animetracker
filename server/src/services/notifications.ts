import { and, desc, eq, inArray, isNull, sql } from 'drizzle-orm'
import { db } from '../db/index.js'
import { notifications } from '../db/schema.js'
import type { NotificationItem } from '../types/api.js'

/** Newest-first notifications for a user, plus the unread count (for badging). */
export async function listNotifications(userId: string, limit = 50): Promise<{ items: NotificationItem[]; unread: number }> {
  const rows = await db
    .select()
    .from(notifications)
    .where(eq(notifications.userId, userId))
    .orderBy(desc(notifications.createdAt))
    .limit(limit)

  const [countRow] = await db
    .select({ unread: sql<number>`count(*)::int` })
    .from(notifications)
    .where(and(eq(notifications.userId, userId), isNull(notifications.readAt)))

  return {
    items: rows.map((r) => ({
      id: r.id,
      franchiseId: r.franchiseId,
      kind: r.kind,
      title: r.title,
      body: r.body,
      createdAt: r.createdAt.getTime(),
      readAt: r.readAt ? r.readAt.getTime() : null,
    })),
    unread: countRow?.unread ?? 0,
  }
}

/** Mark the given notifications read (or all unread ones when ids is omitted). Returns the count. */
export async function markNotificationsRead(userId: string, ids?: string[]): Promise<number> {
  const scope = ids?.length
    ? and(eq(notifications.userId, userId), isNull(notifications.readAt), inArray(notifications.id, ids))
    : and(eq(notifications.userId, userId), isNull(notifications.readAt))
  const updated = await db.update(notifications).set({ readAt: new Date() }).where(scope).returning({ id: notifications.id })
  return updated.length
}
