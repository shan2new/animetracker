import { assertAuthConfig, authConfigFromEnv } from './auth/authConfig.js'
import { env } from './env.js'
import { buildServer } from './server.js'
import { startCron } from './sync/cron.js'

// Fail closed BEFORE anything is built: a production process that enables the dev bearer issuer,
// or that has no way to verify a real Clerk token, must not open a pool or a socket. Runs ahead of
// buildServer() so the reason is the first thing printed rather than the second failure in a chain.
try {
  assertAuthConfig(authConfigFromEnv())
} catch (err) {
  console.error(err instanceof Error ? err.message : err)
  process.exit(1)
}

const app = await buildServer()

try {
  await app.listen({ port: env.PORT, host: '0.0.0.0' })
  startCron()
  app.log.info(`AniTrack server listening on :${env.PORT} (APP_ENV=${env.APP_ENV})`)
} catch (err) {
  app.log.error(err)
  process.exit(1)
}
