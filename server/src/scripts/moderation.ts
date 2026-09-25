// The operator's moderation console: `npm run moderation -- <command> [flags]`
// (`npm run moderation -- help` for the list). Argument grammar: scripts/moderationArgs.ts.
// IO: services/moderation.ts. Prints plain-text tables; exits non-zero on any error.
//
// It writes straight to the database this process is configured for (DATABASE_URL), so a ban
// reaches the running server on its next ban-list refresh (SOCIAL_BAN_CACHE_SECONDS).
import { sql } from '../db/index.js'
import {
  banUser,
  dismissReports,
  getCommentDetail,
  hideComment,
  listActiveBans,
  listReportQueue,
  ModerationError,
  resetIdentity,
  restoreComment,
  unbanUser,
} from '../services/moderation.js'
import { retryClerkErasure } from '../services/erasure.js'
import { MODERATION_USAGE, parseModerationArgs, type ModerationCommand } from './moderationArgs.js'

/** Left-aligned columns separated by two spaces, with a rule under the header. */
function table(headers: string[], rows: string[][]): string {
  const widths = headers.map((h, i) => Math.max([...h].length, ...rows.map((r) => [...(r[i] ?? '')].length)))
  const line = (cells: string[]) =>
    cells
      .map((c, i) => (i === cells.length - 1 ? c : c + ' '.repeat(Math.max(0, widths[i]! - [...c].length))))
      .join('  ')
      .trimEnd()
  return [line(headers), line(widths.map((w) => '-'.repeat(w))), ...rows.map(line)].join('\n')
}

/** "3d 4h", "5h 12m", "42m", "just now". */
function age(fromMs: number, nowMs: number): string {
  const minutes = Math.max(0, Math.floor((nowMs - fromMs) / 60_000))
  if (minutes < 1) return 'just now'
  const days = Math.floor(minutes / 1440)
  const hours = Math.floor((minutes % 1440) / 60)
  const mins = minutes % 60
  if (days > 0) return `${days}d ${hours}h`
  if (hours > 0) return `${hours}h ${mins}m`
  return `${mins}m`
}

/** "just now" or "3d 4h ago". */
function ago(fromMs: number, nowMs: number): string {
  const text = age(fromMs, nowMs)
  return text === 'just now' ? text : `${text} ago`
}

const iso = (d: Date | null): string => (d ? d.toISOString() : '-')
const who = (handle: string | null, clerkId: string): string => (handle ? `@${handle} (${clerkId})` : clerkId)

function state(c: { hiddenAt: Date | null; hiddenReason: string | null; deletedAt: Date | null }): string {
  if (c.deletedAt) return 'deleted'
  if (c.hiddenAt) return `hidden (${c.hiddenReason ?? 'unknown'})`
  return 'visible'
}

async function run(cmd: ModerationCommand): Promise<number> {
  const now = Date.now()
  switch (cmd.command) {
    case 'help':
      console.log(MODERATION_USAGE)
      return 0

    case 'list': {
      const queue = await listReportQueue({ all: cmd.all, limit: cmd.limit })
      if (queue.length === 0) {
        console.log(cmd.all ? 'No reports.' : 'No open reports.')
        return 0
      }
      console.log(
        table(
          ['COMMENT', 'SUBJECT', 'AUTHOR', 'COUNT', 'LISTED', 'REASONS', 'STATE', 'WAITING', 'BODY'],
          queue.map((e) => [
            e.commentId,
            e.subject,
            who(e.authorHandle, e.authorClerkId),
            String(e.reportCount),
            String(e.reports),
            e.reasons.join(','),
            state(e),
            age(e.oldestReportAt, now),
            JSON.stringify(e.bodyPreview),
          ]),
        ),
      )
      console.log(`\n${queue.length} comment(s)${queue.length === cmd.limit ? ` (limit ${cmd.limit}; --limit N for more)` : ''}.`)
      return 0
    }

    case 'show': {
      const detail = await getCommentDetail(cmd.commentId)
      if (!detail) throw new ModerationError(`comment ${cmd.commentId} not found`)
      const { comment: c, author: a } = detail
      console.log(
        [
          `Comment   ${c.id}`,
          `Subject   ${c.subject}`,
          `Franchise ${c.franchiseId}`,
          `Parent    ${c.parentId ?? '-'}`,
          `Author    ${who(a.handle, a.clerkId)}${a.displayName ? ` "${a.displayName}"` : ''} user ${a.userId}${a.banned ? ' [BANNED]' : ''}`,
          `Created   ${iso(c.createdAt)} (${ago(c.createdAt.getTime(), now)})`,
          `State     ${state(c)}${c.hiddenAt ? ` since ${iso(c.hiddenAt)}` : ''}${c.deletedAt ? ` at ${iso(c.deletedAt)}` : ''}`,
          `Reports   ${c.reportCount} counted`,
          '',
          c.deletedAt ? '(body erased by the author)' : c.body,
          '',
        ].join('\n'),
      )
      if (detail.reports.length === 0) {
        console.log('No reports.')
        return 0
      }
      console.log(
        table(
          ['REPORTED', 'BY', 'REASON', 'RESOLVED', 'NOTE'],
          detail.reports.map((r) => [
            iso(r.createdAt),
            who(r.reporterHandle, r.reporterClerkId),
            r.reason,
            r.resolvedAt ? `${r.resolution ?? '?'} ${iso(r.resolvedAt)}` : 'open',
            r.note ? JSON.stringify(r.note) : '',
          ]),
        ),
      )
      return 0
    }

    case 'hide': {
      const r = await hideComment(cmd.commentId)
      // The schema records only THAT an operator hid it (hidden_reason = 'operator'); the reason is
      // for the operator's own log, so it goes to the terminal.
      console.log(
        `Hidden ${r.commentId}${cmd.reason ? ` (reason: ${cmd.reason})` : ''}: ` +
          `${r.resolvedReports} report(s) resolved as hidden, ${r.removedNotifications} notification(s) removed.`,
      )
      return 0
    }

    case 'restore': {
      const r = await restoreComment(cmd.commentId)
      console.log(`Restored ${r.commentId}: report count reset, ${r.dismissedReports} open report(s) dismissed.`)
      return 0
    }

    case 'dismiss': {
      const r = await dismissReports(cmd.commentId)
      console.log(`Dismissed ${r.dismissedReports} open report(s) on ${r.commentId}; the comment is unchanged.`)
      return 0
    }

    case 'ban': {
      const r = await banUser(cmd.target, { reason: cmd.reason, hideComments: cmd.hideComments })
      console.log(
        `${r.alreadyBanned ? `Already banned${cmd.reason ? ' (reason updated)' : ''}` : 'Banned'}: ${who(r.handle, r.clerkId)}` +
          `${r.userId ? '' : ' (no account on this server)'}` +
          `${cmd.hideComments ? `; ${r.hiddenComments} comment(s) hidden` : ''}.` +
          '\nThe running server applies it within SOCIAL_BAN_CACHE_SECONDS.',
      )
      return 0
    }

    case 'unban': {
      if (!(await unbanUser(cmd.clerkId))) throw new ModerationError(`${cmd.clerkId} has no active ban`)
      console.log(`Unbanned ${cmd.clerkId}. The running server applies it within SOCIAL_BAN_CACHE_SECONDS.`)
      return 0
    }

    case 'reset-identity': {
      const r = await resetIdentity(cmd.target)
      const was = r.previousHandle
        ? `@${r.previousHandle}${r.previousDisplayName ? ` "${r.previousDisplayName}"` : ''}`
        : r.previousDisplayName
          ? `"${r.previousDisplayName}"`
          : null
      console.log(
        was
          ? `Reset ${r.clerkId}: ${was} cleared. They pick a new name at their next reply; their comments are unlisted until then.`
          : `${r.clerkId} had no public identity; nothing to reset.`,
      )
      return 0
    }

    case 'clerk-delete': {
      const r = await retryClerkErasure(cmd.clerkId)
      switch (r.outcome) {
        case 'deleted':
          console.log(`Deleted the Clerk identity ${cmd.clerkId} (or Clerk no longer had it).`)
          return 0
        case 'banned':
          console.log(`${cmd.clerkId} is suspended: banned in Clerk, kept so its email cannot sign up again.`)
          return 0
        case 'skipped':
          throw new ModerationError('CLERK_SECRET_KEY is not set for this process; nothing was called')
        case 'failed':
          throw new ModerationError(`Clerk refused: ${r.error}`)
      }
    }

    case 'bans': {
      const bans = await listActiveBans()
      if (bans.length === 0) {
        console.log('No active bans.')
        return 0
      }
      console.log(
        table(
          ['CLERK ID', 'HANDLE', 'SINCE', 'REASON'],
          bans.map((b) => [b.clerkId, b.handle ? `@${b.handle}` : '-', iso(b.createdAt), b.reason ?? '']),
        ),
      )
      return 0
    }
  }
}

async function main(): Promise<number> {
  const parsed = parseModerationArgs(process.argv.slice(2))
  if (!parsed.ok) {
    console.error(`moderation: ${parsed.error}\n\n${MODERATION_USAGE}`)
    return 2
  }
  return run(parsed.command)
}

main()
  .then((code) => {
    process.exitCode = code
  })
  .catch((err) => {
    console.error(`moderation: ${err instanceof ModerationError ? err.message : err instanceof Error ? (err.stack ?? err.message) : String(err)}`)
    process.exitCode = 1
  })
  .finally(() => sql.end())
