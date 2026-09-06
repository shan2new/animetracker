import Fastify from 'fastify'
import { describe, expect, it } from 'vitest'
import { legalRoutes } from './legal.js'

// These two URLs are filed with Apple (App Store guideline 5.1.1) and wired into the app's
// Info.plist. A privacy policy that 404s is a rejection, so the contract worth testing is the
// boring one: both paths answer 200 with HTML, without a session, and the page is actually rendered
// rather than a template that leaked `undefined` into the reader's face.
describe('legal routes', () => {
  const build = async () => {
    const app = Fastify()
    await app.register(legalRoutes)
    return app
  }

  for (const [path, heading] of [
    ['/privacy', 'Privacy Policy'],
    ['/terms', 'Terms of Use'],
  ] as const) {
    it(`serves ${path} as public HTML`, async () => {
      const app = await build()
      const res = await app.inject({ method: 'GET', url: path })

      expect(res.statusCode).toBe(200)
      expect(res.headers['content-type']).toMatch(/text\/html/)
      expect(res.body).toContain(`<h1>${heading}</h1>`)
      // A stray `undefined` means an interpolated constant lost its value.
      expect(res.body).not.toContain('undefined')
      // The support address is the one contactable thing on the page; it must survive edits.
      expect(res.body).toContain('mailto:')
      await app.close()
    })
  }

  it('states the deletion route the app actually implements', async () => {
    const app = await build()
    const res = await app.inject({ method: 'GET', url: '/privacy' })
    // `DELETE /me` exists and Profile exposes it; the policy must not promise something else.
    expect(res.body).toContain('Delete Account')
    await app.close()
  })
})
