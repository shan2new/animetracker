import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { fetchOne, gql } from './client.js'

// `client.ts` imports only types, so this suite needs neither env nor a DB — matching the
// no-DB/no-network rule the rest of the suite follows. `fetch` is stubbed per test.
//
// What is pinned here is the retry POLICY, because it is the thing that was wrong: a transient
// AniList 403 used to throw on the first attempt and take a whole daily sync down with it.

const jsonOk = (data: unknown) =>
  new Response(JSON.stringify({ data }), { status: 200, headers: { 'Content-Type': 'application/json' } })

/** Queue a response per call, so a test can say "403 twice, then 200". */
function stubFetch(...responses: (() => Response)[]) {
  const calls: number[] = []
  const fn = vi.fn(async () => {
    const make = responses[Math.min(calls.length, responses.length - 1)]!
    calls.push(1)
    return make()
  })
  vi.stubGlobal('fetch', fn)
  return fn
}

beforeEach(() => {
  vi.useFakeTimers()
})

afterEach(() => {
  vi.useRealTimers()
  vi.unstubAllGlobals()
})

/** Drive a gql call to settlement while fake timers skip the backoff sleeps. */
async function settle<T>(p: Promise<T>): Promise<{ value?: T; error?: Error }> {
  const wrapped = p.then((value) => ({ value }), (error: Error) => ({ error }))
  await vi.runAllTimersAsync()
  return wrapped
}

describe('gql retry policy', () => {
  it('retries a 403 and succeeds when AniList recovers', async () => {
    const f = stubFetch(
      () => new Response('blocked', { status: 403 }),
      () => jsonOk({ Page: { media: [{ id: 1 }] } }),
    )
    const { value, error } = await settle(gql<{ Page: unknown }>('query {}', {}))
    expect(error).toBeUndefined()
    expect(value).toEqual({ Page: { media: [{ id: 1 }] } })
    expect(f).toHaveBeenCalledTimes(2)
  })

  it('gives up on a persistent 403 after the bounded retries, quoting the body', async () => {
    const f = stubFetch(() => new Response('error code: 1020', { status: 403 }))
    const { error } = await settle(gql('query {}', {}))
    // 1 initial attempt + MAX_RETRIES(4) re-attempts.
    expect(f).toHaveBeenCalledTimes(5)
    expect(error?.message).toBe('AniList 403: error code: 1020')
  })

  it('still retries 429 and 5xx', async () => {
    for (const status of [429, 500, 503]) {
      vi.unstubAllGlobals()
      const f = stubFetch(
        () => new Response('slow down', { status }),
        () => jsonOk({ ok: true }),
      )
      const { value } = await settle(gql('query {}', {}))
      expect(value, `status ${status}`).toEqual({ ok: true })
      expect(f, `status ${status}`).toHaveBeenCalledTimes(2)
    }
  })

  it('honors Retry-After on a 429 instead of the exponential default', async () => {
    const f = stubFetch(
      () => new Response('slow down', { status: 429, headers: { 'Retry-After': '30' } }),
      () => jsonOk({ ok: true }),
    )
    const p = gql('query {}', {})
    await vi.advanceTimersByTimeAsync(29_000)
    expect(f).toHaveBeenCalledTimes(1) // still waiting out the 30s the header asked for
    await vi.advanceTimersByTimeAsync(2_000)
    expect(f).toHaveBeenCalledTimes(2)
    await expect(p).resolves.toEqual({ ok: true })
  })

  it('does NOT retry a non-retryable status, and reports the body', async () => {
    const f = stubFetch(() => new Response('Not Found', { status: 404 }))
    const { error } = await settle(gql('query {}', {}))
    expect(f).toHaveBeenCalledTimes(1)
    expect(error?.message).toBe('AniList 404: Not Found')
  })

  it('surfaces GraphQL errors from a 200 response', async () => {
    stubFetch(
      () => new Response(JSON.stringify({ errors: [{ message: 'Invalid token' }] }), { status: 200 }),
    )
    const { error } = await settle(gql('query {}', {}))
    expect(error?.message).toBe('Invalid token')
  })
})

describe('fetchOne 404 handling', () => {
  it('treats a real 404 as "not found" rather than an error', async () => {
    stubFetch(() => new Response('Not Found', { status: 404 }))
    const { value, error } = await settle(fetchOne(123))
    expect(error).toBeUndefined()
    expect(value).toBeNull()
  })

  it('does not mistake a body that merely contains "404" for a 404 status', async () => {
    // The 404 check is anchored on the formatted status, so a 403 whose body happens to mention
    // 404 must still propagate — swallowing it would silently drop a node from the graph walk.
    const f = stubFetch(() => new Response('blocked; see https://example.com/404', { status: 403 }))
    const { error } = await settle(fetchOne(123))
    expect(f).toHaveBeenCalledTimes(5) // retried as a 403, not short-circuited as a 404
    expect(error?.message).toContain('AniList 403')
  })
})
