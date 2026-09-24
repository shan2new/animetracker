/**
 * Spaces calls at least `intervalMs` apart: await it before each provider request. The first call
 * passes at once. AniList drops to 30 requests/minute when degraded, so background sweeps that make
 * a variable number of requests per item (an enrichment fetch plus a few root-walk levels) pace
 * every REQUEST rather than sleeping a fixed time per item.
 */
export function createPacer(intervalMs: number): () => Promise<void> {
  let next = 0
  return async () => {
    const now = Date.now()
    const wait = Math.max(0, next - now)
    next = Math.max(now, next) + intervalMs
    if (wait > 0) await new Promise((resolve) => setTimeout(resolve, wait))
  }
}
