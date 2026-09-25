import { assertAuthConfig, authConfigFromEnv } from './auth/authConfig.js'
import { env } from './env.js'
import { buildServer } from './server.js'
import { assertSocialConfig, socialConfigSummary } from './socialConfig.js'
import { startCron } from './sync/cron.js'

// Fail closed BEFORE anything is built: a production process that enables the dev bearer issuer,
// or that has no way to verify a real Clerk token, or that switches the social rate limits off,
// must not open a pool or a socket. Runs ahead of buildServer() so the reason is the first thing
// printed rather than the second failure in a chain.
try {
  assertAuthConfig(authConfigFromEnv())
  assertSocialConfig()
} catch (err) {
  console.error(err instanceof Error ? err.message : err)
  process.exit(1)
}

const app = await buildServer()

try {
  await app.listen({ port: env.PORT, host: '0.0.0.0' })
  startCron()
  app.log.info(`AniTrack server listening on :${env.PORT} (APP_ENV=${env.APP_ENV})`)
  // Which side of the comments launch switch this deploy is on (off unless the host's .env says 1).
  app.log.info(socialConfigSummary())
} catch (err) {
  app.log.error(err)
  process.exit(1)
}
