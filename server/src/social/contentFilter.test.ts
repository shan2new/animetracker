import { describe, expect, it } from 'vitest'
import type { BlockedTerm } from './blocklist.js'
import {
  checkCommentBody,
  checkNameText,
  codePointLength,
  COMMENT_MAX_CODE_POINTS,
  containsBlockedTerm,
  containsLink,
  normalizeUserText,
} from './contentFilter.js'

// Never a real term in a test: every blocked-term case injects fakes.
const WORD: BlockedTerm = { term: 'zzbadword', match: 'word' }
const SUB: BlockedTerm = { term: 'zzbad', match: 'substring' }
const PHRASE: BlockedTerm = { term: 'qux quux', match: 'word' }
const FAKE = [WORD] as const

describe('codePointLength', () => {
  it('counts code points, not UTF-16 units', () => {
    expect(codePointLength('abc')).toBe(3)
    expect(codePointLength('👍🏽')).toBe(2) // emoji + skin-tone modifier
    expect('👍🏽'.length).toBe(4)
  })
})

describe('normalizeUserText', () => {
  it('turns CRLF and CR into LF', () => {
    expect(normalizeUserText('a\r\nb\rc', { multiline: true })).toBe('a\nb\nc')
  })

  it('collapses three or more newlines to two and drops trailing spaces before a newline', () => {
    expect(normalizeUserText('a  \t\n\n\n\nb', { multiline: true })).toBe('a\n\nb')
  })

  it('strips zero-width, bidi, BOM and soft-hyphen characters', () => {
    expect(normalizeUserText('﻿a​b‮c⁦d­e', { multiline: true })).toBe('abcde')
  })

  it('single-line folds every whitespace run to one space and trims', () => {
    expect(normalizeUserText('  Mary \n\t Jane  ', { multiline: false })).toBe('Mary Jane')
  })

  it('composes to NFC', () => {
    expect(normalizeUserText('Zoë', { multiline: false })).toBe('Zoë')
  })
})

describe('checkCommentBody', () => {
  it('accepts exactly 280 plain code points and refuses 281 as too_long', () => {
    expect(checkCommentBody('a'.repeat(COMMENT_MAX_CODE_POINTS))).toEqual({ ok: true, text: 'a'.repeat(280) })
    expect(checkCommentBody('a'.repeat(281))).toEqual({ ok: false, reason: 'too_long' })
  })

  it('counts 280 emoji with a skin tone as 560 code points, and refuses them', () => {
    expect(checkCommentBody('👍🏽'.repeat(280))).toEqual({ ok: false, reason: 'too_long' })
    expect(checkCommentBody('👍🏽'.repeat(140)).ok).toBe(true)
  })

  it('strips zero-width characters BEFORE counting', () => {
    expect(checkCommentBody(`${'a'.repeat(280)}​​`)).toEqual({ ok: true, text: 'a'.repeat(280) })
  })

  it('stores the normalised text', () => {
    expect(checkCommentBody('  great\r\n\r\n\r\n\r\nepisode  ')).toEqual({ ok: true, text: 'great\n\nepisode' })
  })

  it('refuses empty text, including text that is empty only after normalisation', () => {
    expect(checkCommentBody('')).toEqual({ ok: false, reason: 'empty' })
    expect(checkCommentBody('  \n​\t ')).toEqual({ ok: false, reason: 'empty' })
  })

  it('refuses C0/C1 controls as invalid_characters, but keeps tabs and newlines', () => {
    expect(checkCommentBody('bad\u0007bell')).toEqual({ ok: false, reason: 'invalid_characters' })
    expect(checkCommentBody('bad\u0085nel')).toEqual({ ok: false, reason: 'invalid_characters' })
    expect(checkCommentBody('a\tb\nc').ok).toBe(true)
  })

  it('refuses links', () => {
    expect(checkCommentBody('watch it at example.com')).toEqual({ ok: false, reason: 'link' })
  })

  it('refuses blocked terms from the injected list', () => {
    expect(checkCommentBody('you zzbadword', FAKE)).toEqual({ ok: false, reason: 'blocked_term' })
    expect(checkCommentBody('a fine comment', FAKE).ok).toBe(true)
  })
})

describe('containsLink', () => {
  it.each(['https://x.y', 'see http://a.b/c', 'FTP://files.example', 'www.x', 'WWW.EXAMPLE.ORG', 'example.com', 'discord.gg/abc', 't.me/x', 'example．com', 'foo。com', 'site.io is great', 'my-site.net'])(
    'flags %s',
    (s) => {
      expect(containsLink(s)).toBe(true)
    },
  )

  it.each(['episode.So good', 'how.To', 'Vol.2', 'Dr.Stone', 'Season 1.5', 'the end. Com on', 'I loved it...', 'ep 12 was 10/10'])(
    'leaves %s alone',
    (s) => {
      expect(containsLink(s)).toBe(false)
    },
  )

  // A capital on the label (iOS capitalises a sentence's first word) or an all-caps domain is still
  // a link; only a mixed-case TLD after a dot reads as a sentence.
  it.each(['Example.com', 'DISCORD.GG', 'Visit Telegram.me', 'EXAMPLE.COM', 'Discord.gg is where we are', 'My-Site.NET'])(
    'flags the capitalised domain %s',
    (s) => {
      expect(containsLink(s)).toBe(true)
    },
  )

  it.each(['how.To', 'episode.So good', 'Great.Com on', 'ok.Me too'])('still leaves the mixed-case TLD in %s alone', (s) => {
    expect(containsLink(s)).toBe(false)
  })
})

describe('containsBlockedTerm (injected fake terms only)', () => {
  it('matches a whole word, case- and accent-insensitively', () => {
    expect(containsBlockedTerm('what a ZZBADWORD', [WORD])).toBe(true)
    expect(containsBlockedTerm('what a zzbädwörd', [WORD])).toBe(true)
  })

  it('folds leet digits and symbols', () => {
    expect(containsBlockedTerm('zzb4dw0rd', [WORD])).toBe(true)
    expect(containsBlockedTerm('zzb@dw0rd', [WORD])).toBe(true)
  })

  it('collapses a run of 3+ of one letter to 2 (so a doubled letter in a term survives stretching)', () => {
    expect(containsBlockedTerm('zzzzzzbadword', [WORD])).toBe(true)
    expect(containsBlockedTerm('zzzbadword', [WORD])).toBe(true)
  })

  it('matches the plural in "s"', () => {
    expect(containsBlockedTerm('zzbadwords everywhere', [WORD])).toBe(true)
  })

  it('still matches when punctuation follows the word (the leet map would turn "!" into "i")', () => {
    expect(containsBlockedTerm('you zzbadword!', [WORD])).toBe(true)
    expect(containsBlockedTerm('zzbadword$', [WORD])).toBe(true)
  })

  it('whole-word mode never matches inside a longer word (no Scunthorpe problem)', () => {
    expect(containsBlockedTerm('zzbadwordish', [WORD])).toBe(false)
    expect(containsBlockedTerm('prezzbadword', [WORD])).toBe(false)
  })

  it('substring mode catches spaced-out and punctuated spellings', () => {
    expect(containsBlockedTerm('z z b a d', [SUB])).toBe(true)
    expect(containsBlockedTerm('z.z.b.4.d', [SUB])).toBe(true)
    expect(containsBlockedTerm('prefixzzbadsuffix', [SUB])).toBe(true)
    expect(containsBlockedTerm('zz bat', [SUB])).toBe(false)
  })

  it('matches a multi-word term as a run of whole tokens', () => {
    expect(containsBlockedTerm('well, qux  quux!', [PHRASE])).toBe(true)
    expect(containsBlockedTerm('qux and quux', [PHRASE])).toBe(false)
  })

  it('an empty list or empty text never matches', () => {
    expect(containsBlockedTerm('zzbadword', [])).toBe(false)
    expect(containsBlockedTerm('', [WORD])).toBe(false)
  })
})

describe('checkNameText', () => {
  it.each(['Mira', 'Mary Jane', 'Zoë', '李'])('accepts %s', (name) => {
    expect(checkNameText(name, 40, [WORD])).toEqual({ ok: true, text: name })
  })

  it.each([
    ['', 'empty'],
    ['   ', 'empty'],
    ['a'.repeat(41), 'too_long'],
    ['Mi\u0007ra', 'invalid_characters'],
    ['a@b.com', 'at_sign'],
    ['x.com', 'link'],
    ['123', 'no_letter'],
    ['Mr Zzbadword', 'blocked_term'],
  ] as const)('refuses %j as %s', (name, reason) => {
    expect(checkNameText(name, 40, [WORD])).toEqual({ ok: false, reason })
  })

  it('normalises to one line before measuring', () => {
    expect(checkNameText('  Mary\n\nJane ', 40, [WORD])).toEqual({ ok: true, text: 'Mary Jane' })
  })
})
