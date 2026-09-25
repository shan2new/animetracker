import { describe, expect, it } from 'vitest'
import { DEFAULT_LIST_LIMIT, MAX_LIST_LIMIT, parseModerationArgs } from './moderationArgs.js'

const ID = '0b6c1f2e-3d4a-4b5c-8d6e-7f8091a2b3c4'

const ok = (argv: string[]) => {
  const result = parseModerationArgs(argv)
  if (!result.ok) throw new Error(`expected ok, got: ${result.error}`)
  return result.command
}
const err = (argv: string[]) => {
  const result = parseModerationArgs(argv)
  if (result.ok) throw new Error(`expected an error, got: ${JSON.stringify(result.command)}`)
  return result.error
}

describe('help', () => {
  it('is what nothing, help, --help and -h mean', () => {
    for (const argv of [[], ['help'], ['--help'], ['-h']]) expect(ok(argv)).toEqual({ command: 'help' })
  })

  it('refuses an unknown command', () => {
    expect(err(['purge'])).toMatch(/unknown command "purge"/)
  })
})

describe('list', () => {
  it('defaults to open reports and the default limit', () => {
    expect(ok(['list'])).toEqual({ command: 'list', all: false, limit: DEFAULT_LIST_LIMIT })
  })

  it('takes --all and --limit N in either order, and --limit=N', () => {
    expect(ok(['list', '--all', '--limit', '5'])).toEqual({ command: 'list', all: true, limit: 5 })
    expect(ok(['list', '--limit', '7', '--all'])).toEqual({ command: 'list', all: true, limit: 7 })
    expect(ok(['list', '--limit=9'])).toEqual({ command: 'list', all: false, limit: 9 })
  })

  it('refuses a bad limit', () => {
    expect(err(['list', '--limit'])).toMatch(/--limit needs a value/)
    expect(err(['list', '--limit', '--all'])).toMatch(/--limit needs a value/)
    expect(err(['list', '--limit', 'ten'])).toMatch(/whole number/)
    expect(err(['list', '--limit', '2.5'])).toMatch(/whole number/)
    expect(err(['list', '--limit', '0'])).toMatch(/between 1 and/)
    expect(err(['list', '--limit', String(MAX_LIST_LIMIT + 1)])).toMatch(/between 1 and/)
  })

  it('refuses stray arguments, unknown flags, a repeated flag and a value on a boolean flag', () => {
    expect(err(['list', 'everything'])).toMatch(/unexpected argument "everything"/)
    expect(err(['list', '--reason', 'x'])).toMatch(/unknown flag "--reason" for list/)
    expect(err(['list', '-a'])).toMatch(/unknown flag "-a"/)
    expect(err(['list', '--all', '--all'])).toMatch(/--all given twice/)
    expect(err(['list', '--all=yes'])).toMatch(/--all takes no value/)
  })
})

describe('comment commands', () => {
  it.each(['show', 'restore', 'dismiss'] as const)('%s takes one comment id', (command) => {
    expect(ok([command, ID])).toEqual({ command, commentId: ID })
    expect(ok([command, ID.toUpperCase()])).toEqual({ command, commentId: ID })
    expect(err([command])).toMatch(new RegExp(`${command} needs <commentId>`))
    expect(err([command, 'not-a-uuid'])).toMatch(/is not a comment id/)
    expect(err([command, ID, ID])).toMatch(/unexpected argument/)
    expect(err([command, ID, '--reason', 'x'])).toMatch(/unknown flag/)
  })

  it('hide takes an optional --reason', () => {
    expect(ok(['hide', ID])).toEqual({ command: 'hide', commentId: ID, reason: null })
    expect(ok(['hide', ID, '--reason', 'doxxing'])).toEqual({ command: 'hide', commentId: ID, reason: 'doxxing' })
    expect(ok(['hide', '--reason=spam wave', ID])).toEqual({ command: 'hide', commentId: ID, reason: 'spam wave' })
    expect(err(['hide', ID, '--reason'])).toMatch(/--reason needs a value/)
    expect(err(['hide', ID, '--reason', '   '])).toMatch(/--reason needs some text/)
    expect(err(['hide', ID, '--reason', 'x'.repeat(501)])).toMatch(/longer than 500/)
    expect(err(['hide'])).toMatch(/hide needs <commentId>/)
  })
})

describe('ban', () => {
  it('takes a clerk id', () => {
    expect(ok(['ban', 'user_2abcDEF'])).toEqual({
      command: 'ban',
      target: { kind: 'clerk', clerkId: 'user_2abcDEF' },
      reason: null,
      hideComments: false,
    })
  })

  it('takes a @handle, normalised', () => {
    expect(ok(['ban', '@Mira.K'])).toEqual({
      command: 'ban',
      target: { kind: 'handle', handle: 'mira.k' },
      reason: null,
      hideComments: false,
    })
  })

  it('takes --reason and --hide-comments', () => {
    expect(ok(['ban', '@dex', '--reason', 'slurs', '--hide-comments'])).toEqual({
      command: 'ban',
      target: { kind: 'handle', handle: 'dex' },
      reason: 'slurs',
      hideComments: true,
    })
    expect(ok(['ban', '--hide-comments', 'user_1'])).toMatchObject({ hideComments: true, reason: null })
  })

  it('refuses a missing target, a malformed handle and a malformed clerk id', () => {
    expect(err(['ban'])).toMatch(/ban needs <clerkId\|@handle>/)
    expect(err(['ban', '--reason', 'x'])).toMatch(/ban needs/)
    expect(err(['ban', '@a'])).toMatch(/is not a handle/)
    expect(err(['ban', '@bad-handle'])).toMatch(/is not a handle/)
    expect(err(['ban', 'user 1'])).toMatch(/is not a clerk id/)
    expect(err(['ban', 'user_1', 'user_2'])).toMatch(/unexpected argument "user_2"/)
    expect(err(['ban', 'user_1', '--hide'])).toMatch(/unknown flag "--hide"/)
  })
})

describe('unban and bans', () => {
  it('unban takes a clerk id only', () => {
    expect(ok(['unban', 'user_2abc'])).toEqual({ command: 'unban', clerkId: 'user_2abc' })
    expect(err(['unban'])).toMatch(/unban needs <clerkId>/)
    expect(err(['unban', '@dex'])).toMatch(/clerk id, not a handle/)
    expect(err(['unban', 'user_1', '--reason', 'x'])).toMatch(/unknown flag/)
  })

  it('bans takes nothing', () => {
    expect(ok(['bans'])).toEqual({ command: 'bans' })
    expect(err(['bans', '--all'])).toMatch(/unknown flag "--all" for bans/)
    expect(err(['bans', 'user_1'])).toMatch(/unexpected argument/)
  })

  it('treats everything after -- as positional', () => {
    expect(err(['ban', '--', '--hide-comments'])).toMatch(/is not a clerk id/)
  })
})

describe('reset-identity', () => {
  it('takes a clerk id or a @handle, normalised', () => {
    expect(ok(['reset-identity', 'user_2abc'])).toEqual({
      command: 'reset-identity',
      target: { kind: 'clerk', clerkId: 'user_2abc' },
    })
    expect(ok(['reset-identity', '@Dex.K'])).toEqual({
      command: 'reset-identity',
      target: { kind: 'handle', handle: 'dex.k' },
    })
  })

  it('refuses a missing or malformed target, flags and stray arguments', () => {
    expect(err(['reset-identity'])).toMatch(/reset-identity needs <clerkId\|@handle>/)
    expect(err(['reset-identity', '@a'])).toMatch(/is not a handle/)
    expect(err(['reset-identity', 'user 1'])).toMatch(/is not a clerk id/)
    expect(err(['reset-identity', 'user_1', 'user_2'])).toMatch(/unexpected argument "user_2"/)
    expect(err(['reset-identity', 'user_1', '--reason', 'x'])).toMatch(/unknown flag "--reason" for reset-identity/)
  })
})

describe('clerk-delete', () => {
  it('takes exactly one clerk id', () => {
    expect(ok(['clerk-delete', 'user_2abc'])).toEqual({ command: 'clerk-delete', clerkId: 'user_2abc' })
  })

  it('refuses a handle, a missing or malformed id, extras and flags', () => {
    expect(err(['clerk-delete', '@dex'])).toMatch(/takes a clerk id, not a handle/)
    expect(err(['clerk-delete'])).toMatch(/clerk-delete needs <clerkId>/)
    expect(err(['clerk-delete', 'user 1'])).toMatch(/is not a clerk id/)
    expect(err(['clerk-delete', 'user_1', 'user_2'])).toMatch(/unexpected argument "user_2"/)
    expect(err(['clerk-delete', 'user_1', '--reason', 'x'])).toMatch(/unknown flag "--reason" for clerk-delete/)
  })
})
