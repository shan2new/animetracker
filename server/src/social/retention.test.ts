import { describe, expect, it } from 'vitest'
import { COMMENT_TOMBSTONE_DAYS, isPurgeableTombstone, tombstoneCutoff } from './retention.js'

const NOW = Date.parse('2026-09-25T03:10:00.000Z')
const DAY = 24 * 60 * 60 * 1000

describe('comment tombstone retention', () => {
  it('keeps a tombstone for 30 days', () => {
    expect(COMMENT_TOMBSTONE_DAYS).toBe(30)
    expect(tombstoneCutoff(NOW).toISOString()).toBe('2026-08-26T03:10:00.000Z')
  })

  it('purges only tombstones deleted strictly before the cutoff', () => {
    expect(isPurgeableTombstone(new Date(NOW - 30 * DAY - 1), NOW)).toBe(true)
    expect(isPurgeableTombstone(new Date(NOW - 30 * DAY), NOW)).toBe(false)
    expect(isPurgeableTombstone(new Date(NOW - 29 * DAY), NOW)).toBe(false)
    expect(isPurgeableTombstone(new Date(NOW - 400 * DAY), NOW)).toBe(true)
  })

  it('never purges a live comment', () => {
    expect(isPurgeableTombstone(null, NOW)).toBe(false)
  })
})
