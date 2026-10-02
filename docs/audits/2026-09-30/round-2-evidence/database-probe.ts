// Audit reproduction: real migrated PostgreSQL and routes, synthetic identities, no upstreams.
import assert from 'node:assert/strict'
import { randomUUID } from 'node:crypto'
import { writeFile } from 'node:fs/promises'

const target = new URL(process.env.DATABASE_URL ?? '')
assert.equal(target.hostname, '127.0.0.1')
assert.match(target.pathname, /^\/anitrack_release_audit_tests_20260930_[a-f0-9]{8}$/)
assert.equal(process.env.APP_ENV, 'test')
assert.equal(process.env.DEV_AUTH_BYPASS, '1')
for (const name of ['CLERK_SECRET_KEY', 'CLERK_JWT_KEY', 'CEREBRAS_API_KEY', 'OPENROUTER_API_KEY', 'TMDB_ACCESS_TOKEN']) {
  assert.equal(process.env[name], '')
}
const { buildServer } = await import('../../../../server/src/server.ts')
const { sql } = await import('../../../../server/src/db/index.ts')
const { resetErasures } = await import('../../../../server/src/services/erasure.ts')
const { invalidateBanCache } = await import('../../../../server/src/services/moderation.ts')
const app = await buildServer()
const identityA = 'round-two-synthetic-a', identityB = 'round-two-synthetic-b'
const headersA = { authorization: `Bearer dev:${identityA}` }
const headersB = { authorization: `Bearer dev:${identityB}` }
const result: Record<string, unknown> = { boundary: 'Real SQL/routes, disposable DB, dev identities, no real OAuth or upstream traffic', database: target.pathname.slice(1) }
try {
  const [database] = await sql`select current_database() as name`
  assert.equal(database.name, target.pathname.slice(1))
  for (const headers of [headersA, headersB]) {
    assert.equal((await app.inject({ method: 'GET', url: '/me/profile', headers })).statusCode, 200)
  }
  const [a] = await sql`select id from users where clerk_id=${identityA}`
  const [b] = await sql`select id from users where clerk_id=${identityB}`
  const franchiseId = randomUUID(), parentId = randomUUID(), childId = randomUUID()
  const m1 = 310000011, m2 = 310000012
  await sql`insert into franchise (id,title) values (${franchiseId}, 'Audit synthetic franchise')`
  const nextAiring = JSON.stringify({ episode: 6, airingAt: Math.floor(Date.now()/1000)+86400 })
  await sql`insert into media (id,title_english,status,episodes,next_airing_episode) values (${m1},'Audit releasing','RELEASING',12,${nextAiring}::jsonb), (${m2},'Audit unsized','FINISHED',null,null)`
  await sql`insert into franchise_member (media_id,franchise_id,part_kind,sequence) values (${m1},${franchiseId},'season',1), (${m2},${franchiseId},'season',2)`

  const invalid = [
    { method: 'PUT' as const, url: '/me/preferences', payload: { country: 'invalid' }, headers: headersA },
    { method: 'POST' as const, url: '/me/subscriptions', payload: { franchiseId: 'invalid' }, headers: headersA },
    { method: 'PATCH' as const, url: `/me/subscriptions/${franchiseId}`, payload: { status: 'invalid' }, headers: headersA },
    { method: 'GET' as const, url: '/search?limit=0', headers: headersA },
    { method: 'GET' as const, url: '/franchises/trending?limit=0', headers: headersA },
  ]
  const invalidResults = []
  for (const request of invalid) {
    const response = await app.inject(request)
    assert.equal(response.statusCode, 500, response.body)
    invalidResults.push({ method: request.method, url: request.url, status: response.statusCode, response: response.json() })
  }
  result.invalidInput = invalidResults
  const noMembership = await app.inject({ method: 'PATCH', url: `/me/subscriptions/${franchiseId}`, payload: { status: 'watching' }, headers: headersA })
  assert.equal(noMembership.statusCode, 200)
  const [membership] = await sql`select count(*)::int as n from subscriptions where user_id=${a.id}`
  assert.equal(membership.n, 0)
  result.statusWithoutMembership = { status: noMembership.statusCode, response: noMembership.json(), storedSubscriptions: membership.n }

  const clamped = await app.inject({ method: 'PUT', url: '/me/progress', payload: { mediaId: m1, episodes: 12 }, headers: headersA })
  assert.equal(clamped.statusCode, 200)
  assert.deepEqual(clamped.json(), { ok: true })
  const [saved] = await sql`select episodes_watched from progress where user_id=${a.id} and media_id=${m1}`
  assert.equal(saved.episodes_watched, 5)
  result.clampAcknowledgment = { requested: 12, stored: saved.episodes_watched, response: clamped.json() }

  const tooLargeSingle = await app.inject({ method: 'PUT', url: '/me/progress', payload: { mediaId: m2, episodes: 10000000000 }, headers: headersA })
  assert.equal(tooLargeSingle.statusCode, 400)
  const tooLargeBulk = await app.inject({ method: 'PUT', url: `/me/franchises/${franchiseId}/progress`, payload: { parts: [{ mediaId: m1, episodes: 4 }, { mediaId: m2, episodes: 10000000000 }], status: 'completed' }, headers: headersA })
  assert.equal(tooLargeBulk.statusCode, 500, tooLargeBulk.body)
  const [rollback] = await sql`select episodes_watched from progress where user_id=${a.id} and media_id=${m1}`
  assert.equal(rollback.episodes_watched, 5)
  const [noSecond] = await sql`select count(*)::int as n from progress where user_id=${a.id} and media_id=${m2}`
  assert.equal(noSecond.n, 0)
  result.bulkOverflow = { singleStatus: tooLargeSingle.statusCode, bulkStatus: tooLargeBulk.statusCode, error: tooLargeBulk.json(), priorPartRolledBack: rollback.episodes_watched === 5, secondPartAbsent: noSecond.n === 0 }
  const bulk = await app.inject({ method: 'PUT', url: `/me/franchises/${franchiseId}/progress`, payload: { parts: [{ mediaId: m1, episodes: 3 }, { mediaId: m2, episodes: 2 }], status: 'paused' }, headers: headersA })
  assert.equal(bulk.statusCode, 200, bulk.body)
  result.validAtomicBulk = bulk.json()

  await sql`insert into subscriptions (user_id,franchise_id,status) values (${b.id},${franchiseId},'watching')`
  await sql`insert into progress (user_id,media_id,episodes_watched) values (${b.id},${m1},1)`
  await sql`insert into user_preferences (user_id,country) values (${a.id},'IN')`
  await sql`insert into user_profiles (user_id,handle,display_name) values (${a.id},'audit_a','Audit A'), (${b.id},'audit_b','Audit B') on conflict (user_id) do update set handle=excluded.handle,display_name=excluded.display_name`
  await sql`insert into comments (id,user_id,subject,franchise_id,body) values (${parentId},${a.id},'ep:310000011:1',${franchiseId},'Synthetic parent')`
  await sql`insert into comments (id,user_id,subject,franchise_id,parent_id,body) values (${childId},${b.id},'ep:310000011:1',${franchiseId},${parentId},'Synthetic surviving reply')`
  await sql`insert into comment_likes (user_id,comment_id) values (${b.id},${parentId}),(${a.id},${childId})`
  await sql`insert into reports (user_id,comment_id,reason) values (${b.id},${parentId},'spam'),(${a.id},${childId},'spam')`
  await sql`insert into notifications (user_id,franchise_id,kind,title,body,actor_user_id,comment_id) values (${a.id},${franchiseId},'reply','Audit','',${b.id},${childId}), (${b.id},${franchiseId},'reply','Audit','',${a.id},${parentId}), (${b.id},${franchiseId},'like_comment','Audit','',${b.id},${parentId}), (${b.id},${franchiseId},'reply','Preserve','',${b.id},${childId})`
  await sql`insert into likes (user_id,subject) values (${a.id},'catalog:310000011'),(${b.id},'catalog:310000011')`
  await sql`insert into saves (user_id,post_id,franchise_id) values (${a.id},'catalog:310000011',${franchiseId}),(${b.id},'catalog:310000011',${franchiseId})`
  await sql`insert into reminders (user_id,post_id,franchise_id) values (${a.id},'catalog:310000011',${franchiseId})`
  await sql`insert into feed_hides (user_id,kind,target) values (${a.id},'show',${franchiseId})`
  await sql`insert into episode_ratings (user_id,media_id,episode,score) values (${a.id},${m1},1,60),(${b.id},${m1},1,80)`
  await sql`insert into blocks (user_id,blocked_user_id) values (${a.id},${b.id}),(${b.id},${a.id})`
  await sql`insert into recommendation_feedback (user_id,key,kind) values (${a.id},'anilist:310000011','dismissed')`

  const anonymous = await app.inject({ method: 'GET', url: '/me/export' })
  assert.equal(anonymous.statusCode, 401)
  const forged = await app.inject({ method: 'PUT', url: '/me/progress', payload: { mediaId: m1, episodes: 2, userId: a.id }, headers: headersB })
  assert.equal(forged.statusCode, 400)
  const ownExport = await app.inject({ method: 'GET', url: '/me/export', headers: headersB })
  assert.equal(ownExport.statusCode, 200, ownExport.body)
  assert.equal(ownExport.headers['cache-control'], 'no-store')
  assert.ok(!ownExport.body.includes(identityA))
  assert.ok(!ownExport.body.includes('Synthetic parent'))
  result.ownership = { anonymousExportStatus: anonymous.statusCode, forgedOwnerBodyStatus: forged.statusCode, ownExportStatus: ownExport.statusCode, exportCacheControl: ownExport.headers['cache-control'], otherAuthorPrivateBodyAbsent: true }

  await sql`insert into moderation_bans (clerk_id,reason) values (${identityA},'Synthetic audit ban')`
  invalidateBanCache()
  assert.equal((await app.inject({ method: 'GET', url: '/me/profile', headers: headersA })).statusCode, 403)
  assert.equal((await app.inject({ method: 'GET', url: '/me/export', headers: headersA })).statusCode, 200)
  const deleted = await app.inject({ method: 'DELETE', url: '/me', headers: headersA })
  assert.equal(deleted.statusCode, 200, deleted.body)
  const tableNames = ['users','user_profiles','user_preferences','subscriptions','progress','comments','comment_likes','likes','saves','reminders','feed_hides','episode_ratings','blocks','reports','notifications','recommendation_feedback','moderation_bans']
  const counts: Record<string,number> = {}
  // Table identifiers come exclusively from this literal audit list, never a request.
  for (const name of tableNames) {
    const [count] = await sql`select count(*)::int as n from ${sql(name)}`
    counts[name] = count.n
  }
  assert.deepEqual(counts, { users:1, user_profiles:1, user_preferences:0, subscriptions:1, progress:1, comments:1, comment_likes:0, likes:1, saves:1, reminders:0, feed_hides:0, episode_ratings:1, blocks:0, reports:0, notifications:1, recommendation_feedback:0, moderation_bans:1 })
  const [child] = await sql`select id,user_id,parent_id,body from comments`
  assert.equal(child.id, childId)
  assert.equal(child.user_id, b.id)
  assert.equal(child.parent_id, null)
  assert.equal(child.body, 'Synthetic surviving reply')
  resetErasures()
  const bannedRead = await app.inject({ method:'GET',url:'/me/profile',headers:headersA })
  const bannedExport = await app.inject({ method:'GET',url:'/me/export',headers:headersA })
  assert.equal(bannedRead.statusCode,403)
  assert.equal(bannedExport.statusCode,404)
  const [notRecreated] = await sql`select count(*)::int as n from users where clerk_id=${identityA}`
  assert.equal(notRecreated.n,0)
  result.socialErasure = { response: deleted.json(), remainingTableCounts:counts, otherAuthorReplyPreservedWithNullParent:true, banRetained:true, bannedReadAfterHoldLoss:bannedRead.statusCode, erasedBannedExportAfterHoldLoss:bannedExport.statusCode, erasedBannedAccountRecreated:false }
  await writeFile(new URL('./database-probe-results.json',import.meta.url),JSON.stringify(result,null,2)+'\n')
  console.log('ROUND_TWO_AUDIT',JSON.stringify(result))
} finally {
  await app.close()
  await sql.end({timeout:5})
}
