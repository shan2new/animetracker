import { describe, expect, it, vi } from 'vitest'

vi.mock('../db/index.js', () => ({ db: {} }))

const { applyProviderPreferences } = await import('./preferences.js')

describe('applyProviderPreferences', () => {
  it('puts saved services first and marks them without disturbing the remaining provider order', () => {
    const result = applyProviderPreferences({
      country: 'IN',
      status: 'available',
      providers: [
        { id: 8, name: 'Netflix', logo: null, access: 'subscription' },
        { id: 283, name: 'Crunchyroll', logo: null, access: 'subscription' },
        { id: 119, name: 'Prime Video', logo: null, access: 'subscription' },
      ],
      link: null,
      attribution: 'JustWatch',
    }, [283])

    expect(result.providers).toEqual([
      { id: 283, name: 'Crunchyroll', logo: null, access: 'subscription', preferred: true },
      { id: 8, name: 'Netflix', logo: null, access: 'subscription' },
      { id: 119, name: 'Prime Video', logo: null, access: 'subscription' },
    ])
  })
})
