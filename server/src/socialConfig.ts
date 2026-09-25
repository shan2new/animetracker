import type { AppEnv } from './auth/authConfig.js'
import { env } from './env.js'

// The social layer's boot guard, beside auth/authConfig.ts's: a production process must not come up
// with the per-user rate limits switched off, and every boot states whether public comments are on,
// so the operator can see which side of the launch switch a deploy landed on.

/** The subset of `env` this module reads. Declared structurally so tests can pass a literal. */
export interface SocialEnvSource {
  APP_ENV: AppEnv
  SOCIAL_COMMENTS_ENABLED: boolean
  SOCIAL_RATE_LIMIT_DISABLED: boolean
  SOCIAL_TERMS_VERSION: string
}

/**
 * Fail closed at deploy time. `SOCIAL_RATE_LIMIT_DISABLED` exists for local work (a test client
 * hammering the routes); on a production host it would remove App Review 1.2's abuse control
 * without anyone noticing, so it is a misconfiguration, not a preference.
 */
export function assertSocialConfig(e: SocialEnvSource = env): void {
  if (e.APP_ENV !== 'production') return
  if (e.SOCIAL_RATE_LIMIT_DISABLED) {
    throw new Error(
      'Refusing to start: APP_ENV=production with SOCIAL_RATE_LIMIT_DISABLED enabled. ' +
        'The social rate limits are the abuse control for comments, likes and reports — unset it (or set it to 0).',
    )
  }
}

/** The one line every boot logs: whether public comments are on, and which rules version they need. */
export function socialConfigSummary(e: SocialEnvSource = env): {
  event: 'social.config'
  commentsEnabled: boolean
  termsVersion: string
  rateLimits: boolean
} {
  return {
    event: 'social.config',
    commentsEnabled: e.SOCIAL_COMMENTS_ENABLED,
    termsVersion: e.SOCIAL_TERMS_VERSION,
    rateLimits: !e.SOCIAL_RATE_LIMIT_DISABLED,
  }
}
