import { describe, expect, it } from 'vitest'
import type { FranchiseUpcoming } from '../types/api.js'
import { parseReleaseWindow, resolveReleaseWindow, withReleaseWindow } from './releaseWindow.js'

const key = (s: string) => parseReleaseWindow(s).sortKey
const upcoming = (over: Partial<FranchiseUpcoming>): FranchiseUpcoming => ({
  status: 'announced',
  next: 'Season 2',
  release: 'TBA',
  note: null,
  source: null,
  checked: null,
  ...over,
})

describe('parseReleaseWindow', () => {
  it('reads an ISO day', () => {
    expect(parseReleaseWindow('2026-11-20')).toEqual({ date: '2026-11-20', precision: 'day', sortKey: 20261120 })
  })

  it('reads an ISO month, and does not mistake a year range for one', () => {
    expect(parseReleaseWindow('2026-10')).toEqual({ date: '2026-10', precision: 'month', sortKey: 20261001 })
    // "20" is not a month: this is 2027–2028, a year window.
    expect(parseReleaseWindow('2027-2028')).toEqual({ date: '2027', precision: 'year', sortKey: 20270101 })
  })

  it('reads a month name, which is what the agent actually writes', () => {
    expect(parseReleaseWindow('October 2026')).toEqual({ date: '2026-10', precision: 'month', sortKey: 20261001 })
    expect(parseReleaseWindow('Jan 2027')).toEqual({ date: '2027-01', precision: 'month', sortKey: 20270101 })
    expect(parseReleaseWindow('January 9, 2027')).toEqual({ date: '2027-01-09', precision: 'day', sortKey: 20270109 })
    expect(parseReleaseWindow('9 January 2027')).toEqual({ date: '2027-01-09', precision: 'day', sortKey: 20270109 })
  })

  it('reads a broadcast season as its first month, flagged so nobody prints it', () => {
    expect(parseReleaseWindow('Summer 2027')).toEqual({ date: '2027-07', precision: 'quarter', sortKey: 20270701 })
    expect(parseReleaseWindow('Fall 2026')).toEqual({ date: '2026-10', precision: 'quarter', sortKey: 20261001 })
    expect(parseReleaseWindow('Autumn 2026').sortKey).toBe(20261001)
    expect(parseReleaseWindow('Spring 2027 (Golden Week)')).toEqual({
      date: '2027-04',
      precision: 'quarter',
      sortKey: 20270401,
    })
    expect(parseReleaseWindow('Q3 2026').sortKey).toBe(20260701)
  })

  it('places a vague half-year without claiming a month', () => {
    expect(parseReleaseWindow('Late 2026')).toEqual({ date: '2026', precision: 'year', sortKey: 20260901 })
    expect(parseReleaseWindow('early 2026').sortKey).toBe(20260101)
    // Ordering is the whole point: "late 2026" belongs after spring and before the next year.
    expect(key('Spring 2026')!).toBeLessThan(key('Late 2026')!)
    expect(key('Late 2026')!).toBeLessThan(key('January 2027')!)
  })

  it('falls back to the year, and to nothing at all', () => {
    expect(parseReleaseWindow('2028')).toEqual({ date: '2028', precision: 'year', sortKey: 20280101 })
    for (const s of ['TBA', '', '   ', null, undefined, 'in production']) {
      expect(parseReleaseWindow(s)).toEqual({ date: null, precision: 'unknown', sortKey: null })
    }
  })

  it('finds the date inside a sentence without inventing one from a range', () => {
    // The real corpus. "April 3" has no year of its own, so the window is September 2026 —
    // never April, and never a bare 2026 that would sort the row to New Year's Day.
    const s = "Airing now (April 3 – September 2026, cours 1–2 of 5); remaining 3 cours' dates TBA"
    expect(parseReleaseWindow(s)).toEqual({ date: '2026-09', precision: 'month', sortKey: 20260901 })
  })

  it('orders the corpus the way a reader would', () => {
    const corpus = [
      '2028',
      'Summer 2027',
      'October 2026',
      '2026-08-12',
      'January 2027',
      'TBA',
      'Late 2026',
      '2026-11-20',
      'May 2027',
    ]
    const ordered = corpus
      .map((release) => ({ release, sortKey: parseReleaseWindow(release).sortKey }))
      .sort((a, b) => (a.sortKey ?? Number.MAX_SAFE_INTEGER) - (b.sortKey ?? Number.MAX_SAFE_INTEGER))
      .map((r) => r.release)

    expect(ordered).toEqual([
      '2026-08-12',
      'Late 2026',      // the old ISO-only key put this, and October, in JANUARY 2026 —
      'October 2026',   // ahead of the August date above.
      '2026-11-20',
      'January 2027',
      'May 2027',
      'Summer 2027',
      '2028',
      'TBA',            // undated sorts last, never first
    ])
  })
})

describe('resolveReleaseWindow', () => {
  it('gives a rumor no window, whatever date the rumor names', () => {
    expect(resolveReleaseWindow(upcoming({ status: 'rumored', release: 'January 2027' }))).toEqual({
      date: null,
      precision: 'unknown',
      sortKey: null,
    })
  })

  it('states what every other status knows', () => {
    expect(resolveReleaseWindow(upcoming({ status: 'announced', release: 'January 2027' })).sortKey).toBe(20270101)
    expect(resolveReleaseWindow(upcoming({ status: 'upcoming_dated', release: '2026-11-20' })).precision).toBe('day')
  })

  it('attaches the window without disturbing the stored news', () => {
    const u = upcoming({ release: 'October 2026', note: 'Announced at AnimeJapan.' })
    expect(withReleaseWindow(u)).toEqual({ ...u, releaseWindow: { date: '2026-10', precision: 'month', sortKey: 20261001 } })
    expect(withReleaseWindow(null)).toBeNull()
  })
})
