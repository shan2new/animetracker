// Audit reproduction only. All requests use a synthetic dev identity in a disposable DB.
import assert from 'node:assert/strict'
import { writeFile } from 'node:fs/promises'

const target = new URL(process.env.DATABASE_URL ?? '')
assert.equal(target.hostname, '127.0.0.1')
assert.match(target.pathname, /^\/anitrack_release_audit_tests_20260930_[a-f0-9]{8}$/)
assert.equal(process.env.APP_ENV, 'test')
assert.equal(process.env.DEV_AUTH_BYPASS, '1')
assert.equal(process.env.CLERK_SECRET_KEY, '')
assert.equal(process.env.CLERK_JWT_KEY, '')

const { buildServer } = await import('../../../../server/src/server.ts')
const { sql } = await import('../../../../server/src/db/index.ts')
const { staleOpenReports } = await import('../../../../server/src/services/moderation.ts')
const { resetErasures } = await import('../../../../server/src/services/erasure.ts')
const app = await buildServer()
const headers = { authorization: 'Bearer dev:release-audit-synthetic-identity' }
const result: Record<string, unknown> = {
  boundary: 'Isolated PostgreSQL; real routes and SQL; synthetic dev identity; no Clerk or upstream calls',
  database: target.pathname.slice(1),
}

try {
  const [database] = await sql`select current_database() as name`
  assert.equal(database.name, target.pathname.slice(1))
  const initial = await app.inject({ method: 'GET', url: '/me/profile', headers })
  assert.equal(initial.statusCode, 200, initial.body)
  const [before] = await sql`select id from users where clerk_id = 'release-audit-synthetic-identity'`
  assert.ok(before?.id)
  await sql`insert into user_preferences (user_id, country, language, provider_ids) values (${before.id}, 'IN', 'en', '[8]'::jsonb)`
  await sql`insert into media (id, title_english, format) values (310000001, 'Audit synthetic title', 'TV')`
  await sql`insert into progress (user_id, media_id, episodes_watched) values (${before.id}, 310000001, 7)`

  const deleted = await app.inject({ method: 'DELETE', url: '/me', headers })
  assert.equal(deleted.statusCode, 200, deleted.body)
  assert.deepEqual(deleted.json(), { deleted: true })
  const [remaining] = await sql`select
    (select count(*)::int from users) as users,
    (select count(*)::int from user_preferences) as preferences,
    (select count(*)::int from progress) as progress`
  assert.deepEqual(remaining, { users: 0, preferences: 0, progress: 0 })
  const held = await app.inject({ method: 'GET', url: '/me/profile', headers })
  assert.equal(held.statusCode, 401, held.body)

  // The erasure hold is process memory; clear only the test hook to model its loss on restart.
  resetErasures()
  const recreated = await app.inject({ method: 'GET', url: '/me/profile', headers })
  assert.equal(recreated.statusCode, 200, recreated.body)
  const [after] = await sql`select id from users where clerk_id = 'release-audit-synthetic-identity'`
  assert.ok(after?.id)
  assert.notEqual(after.id, before.id)
  result.erasure = {
    response: deleted.json(), remainingOwnedRows: remaining,
    providerConfiguration: 'No Clerk secret; provider deletion skipped',
    requestDuringMemoryHold: held.statusCode,
    requestAfterMemoryHoldLoss: recreated.statusCode,
    recreatedWithDifferentInternalUserId: after.id !== before.id,
  }

  try {
    result.staleReports = { unexpectedlySucceeded: await staleOpenReports(new Date()) }
    throw new Error('Expected the source Date binding failure to reproduce')
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error)
    assert.match(message, /Received an instance of Date/)
    result.staleReports = { reproduced: true, message }
  }
  console.log('AUDIT_REPRODUCTION', JSON.stringify(result))
  await writeFile(new URL('./real-db-probe-results.json', import.meta.url), JSON.stringify(result, null, 2) + '\n')
} finally {
  await app.close()
  await sql.end({ timeout: 5 })
}
