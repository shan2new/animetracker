import { env } from './env.js'
import { buildServer } from './server.js'
import { startCron } from './sync/cron.js'

const app = await buildServer()

try {
  await app.listen({ port: env.PORT, host: '0.0.0.0' })
  startCron()
  app.log.info(`AniTrack server listening on :${env.PORT}`)
} catch (err) {
  app.log.error(err)
  process.exit(1)
}
