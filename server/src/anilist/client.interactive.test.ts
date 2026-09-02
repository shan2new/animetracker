import { afterEach, describe, expect, it, vi } from 'vitest'
import { gql } from './client.js'

afterEach(() => {
  vi.unstubAllGlobals()
})

describe('interactive AniList request policy', () => {
  it('does not retry a provider failure when maxRetries is zero', async () => {
    const fetch = vi.fn(async () => new Response('blocked', { status: 403 }))
    vi.stubGlobal('fetch', fetch)

    await expect(gql('query {}', {}, { maxRetries: 0, timeoutMs: 100 })).rejects.toThrow('AniList 403')
    expect(fetch).toHaveBeenCalledTimes(1)
  })

  it('aborts retry backoff when the owning search is superseded', async () => {
    const fetch = vi.fn(async () => new Response('temporary', { status: 503 }))
    vi.stubGlobal('fetch', fetch)
    const controller = new AbortController()
    const request = gql('query {}', {}, { signal: controller.signal, maxRetries: 4, timeoutMs: 100 })

    // The first 503 enters its one-second backoff; cancellation must prevent attempt two.
    await Promise.resolve()
    await Promise.resolve()
    controller.abort()
    await expect(request).rejects.toMatchObject({ name: 'AbortError' })
    expect(fetch).toHaveBeenCalledTimes(1)
  })

  it('puts a socket deadline around even the first attempt', async () => {
    const fetch = vi.fn(
      async (_input: string | URL | Request, init?: RequestInit): Promise<Response> =>
        new Promise((_resolve, reject) => {
          const signal = init?.signal
          if (!signal) return reject(new Error('missing signal'))
          signal.addEventListener('abort', () => reject(signal.reason), { once: true })
        }),
    )
    vi.stubGlobal('fetch', fetch)

    await expect(gql('query {}', {}, { maxRetries: 0, timeoutMs: 10 })).rejects.toMatchObject({
      name: 'TimeoutError',
    })
    expect(fetch).toHaveBeenCalledTimes(1)
  })
})
