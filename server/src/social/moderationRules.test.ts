import { describe, expect, it } from 'vitest'
import { autoHideCount, countsTowardAutoHide, reporterCutoff, shouldAutoHide } from './moderationRules.js'

describe('shouldAutoHide — N distinct reporters hide a comment once', () => {
  it('holds below the threshold', () => {
    expect(shouldAutoHide({ reportCount: 0, threshold: 3, hiddenAt: null })).toBe(false)
    expect(shouldAutoHide({ reportCount: 2, threshold: 3, hiddenAt: null })).toBe(false)
  })

  it('hides at the threshold and past it', () => {
    expect(shouldAutoHide({ reportCount: 3, threshold: 3, hiddenAt: null })).toBe(true)
    expect(shouldAutoHide({ reportCount: 7, threshold: 3, hiddenAt: undefined })).toBe(true)
  })

  it('a threshold of 1 hides on the first report', () => {
    expect(shouldAutoHide({ reportCount: 0, threshold: 1, hiddenAt: null })).toBe(false)
    expect(shouldAutoHide({ reportCount: 1, threshold: 1, hiddenAt: null })).toBe(true)
  })

  it('never re-stamps a comment that is already hidden (by reports or by the operator)', () => {
    for (const hiddenAt of [new Date('2026-09-25T10:00:00Z'), 1790330400000, '2026-09-25 10:00:00+00']) {
      expect(shouldAutoHide({ reportCount: 3, threshold: 3, hiddenAt })).toBe(false)
      expect(shouldAutoHide({ reportCount: 50, threshold: 3, hiddenAt })).toBe(false)
    }
  })
})

describe('which reports count toward auto-hide', () => {
  const NOW = Date.UTC(2026, 9, 1, 12)
  const H = 3_600_000
  const opts = { nowMs: NOW, minAgeHours: 24 }

  it('counts an open report from an account at least the minimum age', () => {
    expect(countsTowardAutoHide({ resolvedAt: null, reporterCreatedAt: new Date(NOW - 24 * H) }, opts)).toBe(true)
    expect(countsTowardAutoHide({ resolvedAt: null, reporterCreatedAt: NOW - 400 * H }, opts)).toBe(true)
  })

  it('does not count a reporter younger than the threshold (a fresh account after an erasure)', () => {
    expect(countsTowardAutoHide({ resolvedAt: null, reporterCreatedAt: NOW - 24 * H + 1 }, opts)).toBe(false)
    expect(countsTowardAutoHide({ resolvedAt: null, reporterCreatedAt: NOW }, opts)).toBe(false)
  })

  it('does not count a resolved report', () => {
    expect(countsTowardAutoHide({ resolvedAt: new Date(NOW - H), reporterCreatedAt: NOW - 400 * H }, opts)).toBe(false)
  })

  it('a minimum age of 0 counts every open report', () => {
    expect(countsTowardAutoHide({ resolvedAt: null, reporterCreatedAt: NOW }, { nowMs: NOW, minAgeHours: 0 })).toBe(true)
    expect(reporterCutoff(NOW, 0).getTime()).toBe(NOW)
    expect(reporterCutoff(NOW, 24).getTime()).toBe(NOW - 24 * H)
  })

  it('one person cycling accounts cannot reach the threshold', () => {
    // Three reports: two from accounts created minutes ago (the same person, re-signed up), one old.
    const reports = [
      { resolvedAt: null, reporterCreatedAt: NOW - 10 * 60_000 },
      { resolvedAt: null, reporterCreatedAt: NOW - 5 * 60_000 },
      { resolvedAt: null, reporterCreatedAt: NOW - 90 * 24 * H },
    ]
    const count = autoHideCount(reports, opts)
    expect(count).toBe(1)
    expect(shouldAutoHide({ reportCount: count, threshold: 3, hiddenAt: null })).toBe(false)
  })
})
