import { describe, expect, it } from 'vitest'
import type { BlockedTerm } from './blocklist.js'
import {
  checkDisplayName,
  checkHandle,
  HANDLE_INNOCENT_WORDS,
  normalizeHandle,
  RESERVED_HANDLE_PREFIXES,
  RESERVED_HANDLES,
  RESERVED_NAME_WORDS,
} from './identity.js'

// Never a real slur in a test: blocked-term cases inject a fake word.
const TERMS: readonly BlockedTerm[] = [{ term: 'zzbadword', match: 'word' }]

describe('normalizeHandle', () => {
  it('trims, drops ONE leading @ and lowercases', () => {
    expect(normalizeHandle('  @Dex  ')).toBe('dex')
    expect(normalizeHandle('@@dex')).toBe('@dex')
    expect(normalizeHandle('Mira.K')).toBe('mira.k')
  })
})

describe('checkHandle', () => {
  it('accepts the valid forms, normalised', () => {
    expect(checkHandle('dex')).toEqual({ ok: true, handle: 'dex' })
    expect(checkHandle('mira.k')).toEqual({ ok: true, handle: 'mira.k' })
    expect(checkHandle('a_1')).toEqual({ ok: true, handle: 'a_1' })
    expect(checkHandle('@Dex')).toEqual({ ok: true, handle: 'dex' })
    expect(checkHandle('abcdefghijklmnopqrst')).toEqual({ ok: true, handle: 'abcdefghijklmnopqrst' })
    // "mod" is reserved only whole or with a separator after it, so ordinary words survive.
    expect(checkHandle('modern_fan')).toEqual({ ok: true, handle: 'modern_fan' })
  })

  it.each([
    ['ab', 'length'],
    ['', 'length'],
    ['@ab', 'length'],
    ['abcdefghijklmnopqrstu', 'length'],
    ['a-b', 'characters'],
    ['zoë', 'characters'],
    ['dex fan', 'characters'],
    ['.dex', 'dots'],
    ['dex.', 'dots'],
    ['d..x', 'dots'],
    ['1234', 'no_letter'],
    ['__1_', 'no_letter'],
    ['admin', 'reserved'],
    ['previouslyfan', 'reserved'],
    ['Official_news', 'reserved'],
    ['mod_team', 'reserved'],
    ['mod.x', 'reserved'],
    ['support123', 'reserved'],
    ['me_', 'reserved'],
  ] as const)('refuses %j as %s', (raw, reason) => {
    expect(checkHandle(raw, TERMS)).toEqual({ ok: false, reason })
  })

  it('stops at the FIRST failing rule, in the documented order', () => {
    // Too long AND bad characters → length; bad characters AND no letter → characters.
    expect(checkHandle('a-very-long-handle-that-goes-on', TERMS)).toEqual({ ok: false, reason: 'length' })
    expect(checkHandle('1-2-3', TERMS)).toEqual({ ok: false, reason: 'characters' })
    // A dot problem is reported before the missing letter.
    expect(checkHandle('.123', TERMS)).toEqual({ ok: false, reason: 'dots' })
  })

  it('matches reserved words with the separators removed', () => {
    expect(checkHandle('a.dmin', TERMS)).toEqual({ ok: false, reason: 'reserved' })
    expect(checkHandle('_admin_', TERMS)).toEqual({ ok: false, reason: 'reserved' })
    expect(checkHandle('mod', TERMS)).toEqual({ ok: false, reason: 'reserved' })
  })

  it('refuses an injected blocked term spaced by separators, run together, or leet-spelled', () => {
    expect(checkHandle('zzbadword', TERMS)).toEqual({ ok: false, reason: 'blocked_term' })
    expect(checkHandle('big_zzbadword', TERMS)).toEqual({ ok: false, reason: 'blocked_term' })
    expect(checkHandle('zzbadword.fan', TERMS)).toEqual({ ok: false, reason: 'blocked_term' })
    expect(checkHandle('zzb4dw0rd', TERMS)).toEqual({ ok: false, reason: 'blocked_term' })
  })

  it('refuses a term of 4+ folded letters run into anything else, in any match mode', () => {
    // A handle is one token: a whole-word check alone let "xslurx" and "slur123" through.
    expect(checkHandle('zzbadwordy', TERMS)).toEqual({ ok: false, reason: 'blocked_term' })
    expect(checkHandle('xzzbadwordx', TERMS)).toEqual({ ok: false, reason: 'blocked_term' })
    expect(checkHandle('zzbadword123', TERMS)).toEqual({ ok: false, reason: 'blocked_term' })
    expect(checkHandle('xzzb4dw0rdx', TERMS)).toEqual({ ok: false, reason: 'blocked_term' })
    // Separators removed first: "zz.bad_word" is the run-together term.
    expect(checkHandle('zz.bad_wordx', TERMS)).toEqual({ ok: false, reason: 'blocked_term' })
  })

  it('keeps a term shorter than 4 folded letters whole-word only', () => {
    const short: readonly BlockedTerm[] = [{ term: 'zzq', match: 'word' }]
    expect(checkHandle('zzq', short)).toEqual({ ok: false, reason: 'blocked_term' })
    expect(checkHandle('big_zzq', short)).toEqual({ ok: false, reason: 'blocked_term' })
    expect(checkHandle('zzqfan', short)).toEqual({ ok: true, handle: 'zzqfan' })
  })

  it('cuts innocent words out before the anywhere-match, without joining what is left', () => {
    const innocent = ['yzzbadwordy']
    expect(checkHandle('yzzbadwordy_fan', TERMS, innocent)).toEqual({ ok: true, handle: 'yzzbadwordy_fan' })
    // The term outside the innocent word is still found; a cut leaves a break, never a join.
    expect(checkHandle('yzzbadwordyzzbadword', TERMS, innocent)).toEqual({ ok: false, reason: 'blocked_term' })
    expect(checkHandle('zzbadyzzbadwordyword', TERMS, innocent)).toEqual({ ok: true, handle: 'zzbadyzzbadwordyword' })
    // Set apart by a separator, the term is a whole word again and refused.
    expect(checkHandle('y_zzbadword', TERMS, ['yzzbadword'])).toEqual({ ok: false, reason: 'blocked_term' })
  })

  it('checks the real lists by default without refusing ordinary names', () => {
    expect(checkHandle('sakamoto_days')).toEqual({ ok: true, handle: 'sakamoto_days' })
    for (const handle of [
      'grape_soda',
      'peacock',
      'analog_kid',
      'spicy_ramen',
      'stardust',
      'torpedo',
      'thorny',
      'kuroshitsuji_fan',
      'tardis_blue',
    ]) {
      expect(checkHandle(handle), handle).toEqual({ ok: true, handle })
    }
  })

  it('keeps the innocent words lowercase letters only', () => {
    for (const word of HANDLE_INNOCENT_WORDS) expect(word).toMatch(/^[a-z]+$/)
  })

  it('keeps the reserved list lowercase and in handle grammar', () => {
    for (const word of RESERVED_HANDLES) expect(word).toMatch(/^[a-z]+$/)
    for (const prefix of RESERVED_HANDLE_PREFIXES) expect(prefix).toMatch(/^[a-z]+[._]?$/)
  })
})

describe('checkDisplayName', () => {
  it.each(['Mira', 'Mary Jane', 'Zoë', '李'])('accepts %j', (raw) => {
    expect(checkDisplayName(raw, TERMS)).toEqual({ ok: true, displayName: raw })
  })

  it('stores the normalised single-line form', () => {
    expect(checkDisplayName('  Mary \n  Jane​ ', TERMS)).toEqual({ ok: true, displayName: 'Mary Jane' })
    // NFC: a decomposed "e" + combining diaeresis is stored composed.
    expect(checkDisplayName('Zoë', TERMS)).toEqual({ ok: true, displayName: 'Zoë' })
  })

  it('counts code points: 40 are fine, 41 are too long', () => {
    expect(checkDisplayName('a'.repeat(40), TERMS)).toEqual({ ok: true, displayName: 'a'.repeat(40) })
    expect(checkDisplayName('a'.repeat(41), TERMS)).toEqual({ ok: false, reason: 'too_long' })
    // 40 astral letters are 80 UTF-16 units and still 40 code points.
    const astral = '𝒜'.repeat(40)
    expect(checkDisplayName(astral, TERMS)).toEqual({ ok: true, displayName: astral })
  })

  it.each([
    ['', 'empty'],
    ['   ​ ', 'empty'],
    ['Mira\u0007', 'invalid_characters'],
    ['a@b.com', 'at_sign'],
    ['mira@home', 'at_sign'],
    ['x.com', 'link'],
    ['see www.site', 'link'],
    ['123', 'no_letter'],
    ['!!!', 'no_letter'],
    ['Mr Zzbadword', 'blocked_term'],
  ] as const)('refuses %j as %s', (raw, reason) => {
    expect(checkDisplayName(raw, TERMS)).toEqual({ ok: false, reason })
  })

  it.each([
    'Previously.',
    'Previously Support',
    'Moderator',
    'Mods',
    'Official',
    'Crunchyroll',
    'Netflix Japan',
    'The Team',
    'Adm1n',
    'A.d.m.i.n',
    'Pre-viously',
  ])('refuses %j as reserved', (raw) => {
    expect(checkDisplayName(raw, TERMS)).toEqual({ ok: false, reason: 'reserved' })
  })

  it.each(['Modesty', 'Steam', 'Teamo', 'Supporto'])('does not reserve %j, which only contains a word', (raw) => {
    expect(checkDisplayName(raw, TERMS)).toEqual({ ok: true, displayName: raw })
  })

  it('reports a blocked term before a reserved word', () => {
    expect(checkDisplayName('Zzbadword Support', TERMS)).toEqual({ ok: false, reason: 'blocked_term' })
  })

  it('keeps the reserved name list lowercase letters only', () => {
    for (const word of RESERVED_NAME_WORDS) expect(word).toMatch(/^[a-z]+$/)
  })
})
