import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'
import { envSchema } from './env.js'

// CLAUDE.md: "Every key with a default must also appear in .env.example (they drifted once — keep
// them synced)." They had drifted again (the NEWS_* keys); this holds the file to the schema.

const example = readFileSync(new URL('../.env.example', import.meta.url), 'utf8')
const keys = Object.keys(envSchema.shape)

/** `KEY=value` lines of the example, comments and blanks skipped. */
function exampleValues(): Record<string, string> {
  const out: Record<string, string> = {}
  for (const line of example.split('\n')) {
    const m = /^([A-Z0-9_]+)=(.*)$/.exec(line)
    if (m) out[m[1]!] = m[2]!
  }
  return out
}

describe('.env.example', () => {
  it.each(keys)('lists %s', (key) => {
    expect(example).toMatch(new RegExp(`^${key}=`, 'm'))
  })

  it('parses under the schema as written, so copying it to .env boots', () => {
    expect(envSchema.safeParse(exampleValues()).success).toBe(true)
  })

  it('states the social defaults the contract documents', () => {
    const v = exampleValues()
    const parsed = envSchema.parse(v)
    const defaults = envSchema.parse({})
    // The one deliberate difference: comments are ON in a local copy and OFF by default.
    for (const key of keys.filter((k) => k.startsWith('SOCIAL_') && k !== 'SOCIAL_COMMENTS_ENABLED')) {
      expect(parsed[key as keyof typeof parsed], key).toEqual(defaults[key as keyof typeof defaults])
    }
  })

  it('turns comments on for a local copy', () => {
    expect(envSchema.parse(exampleValues()).SOCIAL_COMMENTS_ENABLED).toBe(true)
  })
})

describe('SOCIAL_COMMENTS_ENABLED', () => {
  // A production .env written before the social build has no such key: a deploy must not turn
  // public comments on by itself (brief §9 — off until the terms and the production Clerk ship).
  it('defaults to OFF when the key is missing', () => {
    expect(envSchema.parse({}).SOCIAL_COMMENTS_ENABLED).toBe(false)
  })

  it.each([
    ['1', true],
    ['true', true],
    ['0', false],
    ['', false],
  ])('%j → %s', (raw, want) => {
    expect(envSchema.parse({ SOCIAL_COMMENTS_ENABLED: raw }).SOCIAL_COMMENTS_ENABLED).toBe(want)
  })
})

describe('SOCIAL_REPORTER_MIN_AGE_HOURS', () => {
  it('defaults to 24 hours, takes 0, and refuses a negative or fractional value', () => {
    expect(envSchema.parse({}).SOCIAL_REPORTER_MIN_AGE_HOURS).toBe(24)
    expect(envSchema.parse({ SOCIAL_REPORTER_MIN_AGE_HOURS: '0' }).SOCIAL_REPORTER_MIN_AGE_HOURS).toBe(0)
    expect(envSchema.safeParse({ SOCIAL_REPORTER_MIN_AGE_HOURS: '-1' }).success).toBe(false)
    expect(envSchema.safeParse({ SOCIAL_REPORTER_MIN_AGE_HOURS: '1.5' }).success).toBe(false)
  })
})

describe('MODERATION_ALERT_WEBHOOK_URL', () => {
  it('unset or empty means the log only', () => {
    expect(envSchema.parse({}).MODERATION_ALERT_WEBHOOK_URL).toBeUndefined()
    expect(envSchema.parse({ MODERATION_ALERT_WEBHOOK_URL: '  ' }).MODERATION_ALERT_WEBHOOK_URL).toBeUndefined()
  })

  it('takes a plain https URL', () => {
    const url = 'https://hooks.slack.com/services/T000/B000/XXXX'
    expect(envSchema.parse({ MODERATION_ALERT_WEBHOOK_URL: url }).MODERATION_ALERT_WEBHOOK_URL).toBe(url)
  })

  it.each(['http://hooks.example.com/x', 'https://user:pass@hooks.example.com/x', 'not a url', 'ftp://x.example.com'])(
    'refuses to boot with %j',
    (raw) => {
      expect(envSchema.safeParse({ MODERATION_ALERT_WEBHOOK_URL: raw }).success).toBe(false)
    },
  )
})
