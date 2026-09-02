import { describe, expect, it } from 'vitest'
import { buildNewsPrompt, type NewsResearchInput } from './agent.js'

const base = (catalogueSource: NewsResearchInput['catalogueSource']): NewsResearchInput => ({
  title: catalogueSource === 'tmdb' ? 'Selling Sunset' : 'Bleach',
  catalogueSource,
  knownParts: [],
  current: null,
  knownAnnouncements: [],
})

describe('buildNewsPrompt', () => {
  it('uses television authorities and language for TMDB franchises', () => {
    const prompt = buildNewsPrompt(base('tmdb'))
    expect(prompt).toContain('television series "Selling Sunset"')
    expect(prompt).toContain('Netflix Tudum')
    expect(prompt).toContain('Deadline')
    expect(prompt).toContain('NOT_YET_RELEASED')
    expect(prompt).toContain('report and verify that installment first')
    expect(prompt).not.toContain('anime franchise "Selling Sunset"')
  })

  it('keeps anime-specific authorities for AniList franchises', () => {
    const prompt = buildNewsPrompt(base('anilist'))
    expect(prompt).toContain('anime franchise "Bleach"')
    expect(prompt).toContain('Anime News Network')
    expect(prompt).toContain('Crunchyroll News')
  })
})
