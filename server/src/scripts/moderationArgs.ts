import type { BanTarget } from '../services/moderation.js'
import { normalizeHandle } from '../social/identity.js'

// The operator CLI's grammar, `npm run moderation -- <command> [flags]` — pure, so the parsing is
// unit-tested without a database. scripts/moderation.ts runs what this returns.

export const DEFAULT_LIST_LIMIT = 50
export const MAX_LIST_LIMIT = 500
const MAX_REASON_LENGTH = 500

export type { BanTarget }

export type ModerationCommand =
  | { command: 'help' }
  | { command: 'list'; all: boolean; limit: number }
  | { command: 'show'; commentId: string }
  | { command: 'hide'; commentId: string; reason: string | null }
  | { command: 'restore'; commentId: string }
  | { command: 'dismiss'; commentId: string }
  | { command: 'ban'; target: BanTarget; reason: string | null; hideComments: boolean }
  | { command: 'unban'; clerkId: string }
  | { command: 'bans' }
  | { command: 'reset-identity'; target: BanTarget }
  | { command: 'clerk-delete'; clerkId: string }

export type ParseResult = { ok: true; command: ModerationCommand } | { ok: false; error: string }

export const MODERATION_USAGE = `Usage: npm run moderation -- <command> [flags]

  list [--all] [--limit N]                  open reports grouped by comment (--all: resolved too)
  show <commentId>                          the comment, its author and every report
  hide <commentId> [--reason text]          hide it, resolve its reports as hidden, drop its notifications
  restore <commentId>                       un-hide it and reset its report count; dismiss open reports
  dismiss <commentId>                       resolve its open reports as dismissed, leave it as it is
  ban <clerkId|@handle> [--reason text] [--hide-comments]
                                            suspend the identity (takes effect within SOCIAL_BAN_CACHE_SECONDS)
  unban <clerkId>                           lift the ban
  bans                                      active bans
  reset-identity <clerkId|@handle>          clear the handle and display name; they pick again at
                                            their next reply, and their comments are unlisted until then
  clerk-delete <clerkId>                    retry erasing an ERASED account's Clerk identity after
                                            account.clerk_delete_failed (banned there instead if suspended)`

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
/** A Clerk user id (`user_…`) or a dev issuer id: no whitespace, not a flag, not a handle. */
const CLERK_ID_RE = /^[^\s@-]\S{0,190}$/
const HANDLE_RE = /^[a-z0-9_.]{3,20}$/

interface FlagSpec {
  /** A value flag takes the next argument (or `--flag=value`); a boolean flag takes none. */
  value: boolean
}

const COMMANDS: Record<Exclude<ModerationCommand['command'], 'help'>, { positionals: string[]; flags: Record<string, FlagSpec> }> = {
  list: { positionals: [], flags: { all: { value: false }, limit: { value: true } } },
  show: { positionals: ['commentId'], flags: {} },
  hide: { positionals: ['commentId'], flags: { reason: { value: true } } },
  restore: { positionals: ['commentId'], flags: {} },
  dismiss: { positionals: ['commentId'], flags: {} },
  ban: { positionals: ['clerkId|@handle'], flags: { reason: { value: true }, 'hide-comments': { value: false } } },
  unban: { positionals: ['clerkId'], flags: {} },
  bans: { positionals: [], flags: {} },
  'reset-identity': { positionals: ['clerkId|@handle'], flags: {} },
  'clerk-delete': { positionals: ['clerkId'], flags: {} },
}

const fail = (error: string): ParseResult => ({ ok: false, error })

function isCommand(name: string): name is keyof typeof COMMANDS {
  return Object.prototype.hasOwnProperty.call(COMMANDS, name)
}

function commentIdOf(raw: string): string | null {
  return UUID_RE.test(raw) ? raw.toLowerCase() : null
}

/** `@handle` (normalised) or a clerk id: whom `ban` and `reset-identity` act on. */
function accountTargetOf(raw: string): BanTarget | { error: string } {
  if (raw.startsWith('@')) {
    const handle = normalizeHandle(raw)
    if (!HANDLE_RE.test(handle)) return { error: `"${raw}" is not a handle` }
    return { kind: 'handle', handle }
  }
  if (!CLERK_ID_RE.test(raw)) return { error: `"${raw}" is not a clerk id` }
  return { kind: 'clerk', clerkId: raw }
}

function reasonOf(raw: string | undefined): string | null | { error: string } {
  if (raw === undefined) return null
  const reason = raw.trim()
  if (reason.length === 0) return { error: '--reason needs some text' }
  if (reason.length > MAX_REASON_LENGTH) return { error: `--reason is longer than ${MAX_REASON_LENGTH} characters` }
  return reason
}

/**
 * Parse `argv` (what follows `npm run moderation --`). Nothing, `help`, `--help` or `-h` is the
 * usage. Every command takes exactly its positionals and only its own flags; a value flag takes
 * the next argument or `--flag=value`; a flag given twice, an unknown flag and a stray argument
 * are errors, so an operator's typo never runs a different command than the one they meant.
 */
export function parseModerationArgs(argv: readonly string[]): ParseResult {
  const [name, ...rest] = argv
  if (name === undefined || name === 'help' || name === '--help' || name === '-h') {
    return { ok: true, command: { command: 'help' } }
  }
  if (!isCommand(name)) return fail(`unknown command "${name}"`)
  const spec = COMMANDS[name]

  const positionals: string[] = []
  const flags = new Map<string, string | true>()
  let flagsDone = false
  for (let i = 0; i < rest.length; i++) {
    const arg = rest[i]!
    if (!flagsDone && arg === '--') {
      flagsDone = true
      continue
    }
    if (flagsDone || !arg.startsWith('--')) {
      if (!flagsDone && /^-[^-]/.test(arg) && !/^-\d/.test(arg)) return fail(`unknown flag "${arg}" for ${name}`)
      positionals.push(arg)
      continue
    }
    const eq = arg.indexOf('=')
    const flag = eq === -1 ? arg.slice(2) : arg.slice(2, eq)
    const flagSpec = spec.flags[flag]
    if (!flagSpec) return fail(`unknown flag "--${flag}" for ${name}`)
    if (flags.has(flag)) return fail(`--${flag} given twice`)
    if (!flagSpec.value) {
      if (eq !== -1) return fail(`--${flag} takes no value`)
      flags.set(flag, true)
      continue
    }
    let value: string | undefined
    if (eq !== -1) {
      value = arg.slice(eq + 1)
    } else {
      const next = rest[i + 1]
      if (next === undefined || next.startsWith('--')) return fail(`--${flag} needs a value`)
      value = next
      i += 1
    }
    flags.set(flag, value)
  }

  if (positionals.length < spec.positionals.length) {
    return fail(`${name} needs ${spec.positionals.map((p) => `<${p}>`).join(' ')}`)
  }
  if (positionals.length > spec.positionals.length) {
    return fail(`unexpected argument "${positionals[spec.positionals.length]}" for ${name}`)
  }
  const value = (flag: string): string | undefined => {
    const v = flags.get(flag)
    return typeof v === 'string' ? v : undefined
  }

  switch (name) {
    case 'list': {
      let limit = DEFAULT_LIST_LIMIT
      const raw = value('limit')
      if (raw !== undefined) {
        if (!/^\d+$/.test(raw)) return fail('--limit must be a whole number')
        limit = Number(raw)
        if (limit < 1 || limit > MAX_LIST_LIMIT) return fail(`--limit must be between 1 and ${MAX_LIST_LIMIT}`)
      }
      return { ok: true, command: { command: 'list', all: flags.has('all'), limit } }
    }
    case 'show':
    case 'restore':
    case 'dismiss':
    case 'hide': {
      const commentId = commentIdOf(positionals[0]!)
      if (!commentId) return fail(`"${positionals[0]}" is not a comment id (a uuid)`)
      if (name !== 'hide') return { ok: true, command: { command: name, commentId } }
      const reason = reasonOf(value('reason'))
      if (reason !== null && typeof reason === 'object') return fail(reason.error)
      return { ok: true, command: { command: 'hide', commentId, reason } }
    }
    case 'ban': {
      const target = accountTargetOf(positionals[0]!)
      if ('error' in target) return fail(target.error)
      const reason = reasonOf(value('reason'))
      if (reason !== null && typeof reason === 'object') return fail(reason.error)
      return { ok: true, command: { command: 'ban', target, reason, hideComments: flags.has('hide-comments') } }
    }
    case 'unban': {
      const raw = positionals[0]!
      if (raw.startsWith('@')) return fail('unban takes a clerk id, not a handle (see `bans`)')
      if (!CLERK_ID_RE.test(raw)) return fail(`"${raw}" is not a clerk id`)
      return { ok: true, command: { command: 'unban', clerkId: raw } }
    }
    case 'bans':
      return { ok: true, command: { command: 'bans' } }
    case 'reset-identity': {
      const target = accountTargetOf(positionals[0]!)
      if ('error' in target) return fail(target.error)
      return { ok: true, command: { command: 'reset-identity', target } }
    }
    case 'clerk-delete': {
      const raw = positionals[0]!
      if (raw.startsWith('@')) return fail('clerk-delete takes a clerk id, not a handle (the account is already erased)')
      if (!CLERK_ID_RE.test(raw)) return fail(`"${raw}" is not a clerk id`)
      return { ok: true, command: { command: 'clerk-delete', clerkId: raw } }
    }
  }
}
