import { describe, expect, it } from 'vitest'
import { envSchema } from './env.js'
import { assertSocialConfig, socialConfigSummary, type SocialEnvSource } from './socialConfig.js'

function source(over: Partial<SocialEnvSource> = {}): SocialEnvSource {
  return {
    APP_ENV: 'production',
    SOCIAL_COMMENTS_ENABLED: false,
    SOCIAL_RATE_LIMIT_DISABLED: false,
    SOCIAL_TERMS_VERSION: '2026-09-25.2',
    ...over,
  }
}

describe('assertSocialConfig', () => {
  it('refuses a production process with the rate limits switched off', () => {
    expect(() => assertSocialConfig(source({ SOCIAL_RATE_LIMIT_DISABLED: true }))).toThrow(
      /APP_ENV=production with SOCIAL_RATE_LIMIT_DISABLED/,
    )
  })

  it('lets a production process boot with comments on or off, limits on', () => {
    expect(() => assertSocialConfig(source())).not.toThrow()
    expect(() => assertSocialConfig(source({ SOCIAL_COMMENTS_ENABLED: true }))).not.toThrow()
  })

  it('allows switching the limits off outside production', () => {
    for (const APP_ENV of ['development', 'test'] as const) {
      expect(() => assertSocialConfig(source({ APP_ENV, SOCIAL_RATE_LIMIT_DISABLED: true }))).not.toThrow()
    }
  })

  it('passes a host .env that predates the social keys', () => {
    expect(() => assertSocialConfig(envSchema.parse({ APP_ENV: 'production' }))).not.toThrow()
  })
})

describe('socialConfigSummary', () => {
  it('states whether comments are on — off for a host .env with no key', () => {
    expect(socialConfigSummary(envSchema.parse({ APP_ENV: 'production' }))).toEqual({
      event: 'social.config',
      commentsEnabled: false,
      termsVersion: envSchema.parse({}).SOCIAL_TERMS_VERSION,
      rateLimits: true,
    })
    expect(socialConfigSummary(source({ SOCIAL_COMMENTS_ENABLED: true })).commentsEnabled).toBe(true)
  })
})
