/**
 * Deploy test for the "production rejects dev-bypass tokens" P0 (spec board 13).
 *
 *   npm run auth:smoke -- https://anime.cognipin.com
 *
 * Asserts two things against a REAL deployed host, from outside the process:
 *   1. GET /health                     → 200            (the host is up and it is ours)
 *   2. GET /me/library with a dev token → 401            (the non-production issuer is refused)
 *
 * Exits 0 when both hold, 1 otherwise — printing the status and the first 200 bytes of the body so
 * a failure is diagnosable without a second round-trip. Safe to run against staging first.
 */
export {} // top-level await needs this file to be a module; it imports nothing on purpose.

const base = (process.argv[2] ?? '').replace(/\/+$/, '')
if (!base) {
  console.error('usage: npm run auth:smoke -- <base-url>   e.g. https://anime.cognipin.com')
  process.exit(1)
}

const TIMEOUT_MS = 15_000

async function probe(path: string, headers: Record<string, string> = {}) {
  const res = await fetch(`${base}${path}`, { headers, signal: AbortSignal.timeout(TIMEOUT_MS) })
  const body = (await res.text()).slice(0, 200)
  return { status: res.status, body }
}

function fail(what: string, expected: number, got: { status: number; body: string }): never {
  console.error(`FAIL  ${what}: expected ${expected}, got ${got.status}`)
  console.error(`      body: ${got.body}`)
  process.exit(1)
}

const devToken = `dev:smoke-${crypto.randomUUID()}`

try {
  const health = await probe('/health')
  if (health.status !== 200) fail('GET /health', 200, health)
  console.log(`ok    GET /health → ${health.status}`)

  const library = await probe('/me/library', { Authorization: `Bearer ${devToken}` })
  if (library.status !== 401) fail(`GET /me/library with "Bearer ${devToken}"`, 401, library)
  console.log(`ok    GET /me/library with a dev: token → ${library.status} ${library.body}`)

  console.log(`\nPASS  ${base} rejects the non-production bearer issuer.`)
} catch (err) {
  console.error(`FAIL  could not reach ${base}: ${err instanceof Error ? err.message : String(err)}`)
  process.exit(1)
}
