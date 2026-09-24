import { describe, expect, it, vi } from 'vitest'
import { createPacer } from './pacer.js'
import { displayTitle } from './text.js'

describe('displayTitle — the short name the apps print (iOS shelfShortened)', () => {
  it('drops a trailing "-Subtitle-" wrapper', () => {
    expect(displayTitle('Re:ZERO -Starting Life in Another World-')).toBe('Re:ZERO')
    expect(displayTitle('TSUKIMICHI -Moonlit Fantasy-')).toBe('TSUKIMICHI')
    expect(displayTitle("KONOSUBA -God's blessing on this wonderful world!")).toBe("KONOSUBA -God's blessing on this wonderful world!")
  })

  it('keeps a title that fits, and the identity half of a long "Title: Subtitle"', () => {
    expect(displayTitle('That Time I Got Reincarnated as a Slime')).toBe('That Time I Got Reincarnated as a Slime')
    expect(displayTitle('Demon Slayer: Kimetsu no Yaiba')).toBe('Demon Slayer: Kimetsu no Yaiba')
    expect(displayTitle('Mushoku Tensei: Jobless Reincarnation Season 2 Part 2')).toBe('Mushoku Tensei')
    expect(displayTitle('HELL MODE: The Hardcore Gamer Dominates in Another World')).toBe('HELL MODE: The Hardcore Gamer Dominates in Another World')
  })

  it('trims stray punctuation and never returns an empty name', () => {
    expect(displayTitle('  Hell’s Paradise  ')).toBe('Hell’s Paradise')
    expect(displayTitle('-')).toBe('-')
  })
})

describe('createPacer', () => {
  it('lets the first call through and spaces the rest', async () => {
    vi.useFakeTimers()
    const pace = createPacer(2_000)
    const seen: number[] = []
    const run = (async () => {
      for (let i = 0; i < 3; i++) {
        await pace()
        seen.push(Date.now())
      }
    })()
    await vi.runAllTimersAsync()
    await run
    expect(seen[1]! - seen[0]!).toBe(2_000)
    expect(seen[2]! - seen[1]!).toBe(2_000)
    vi.useRealTimers()
  })
})
