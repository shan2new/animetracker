import { describe, expect, it } from 'vitest'
import {
  buildGenreTiles,
  decodeGenreCursor,
  encodeGenreCursor,
  EXCLUDED_SOURCE_GENRES,
  GENRES,
  genreByKey,
  genresInScope,
  MAX_GENRE_OFFSET,
  rankGenreTiles,
  sourceGenreNames,
} from './genres.js'
import type { DiscoverGenre, MediaSource } from '../types/api.js'

const SCOPES: (MediaSource | null)[] = [null, 'anilist', 'tmdb']

describe('GENRES vocabulary', () => {
  it('has unique, URL-safe keys and unique names', () => {
    const keys = GENRES.map((def) => def.key)
    expect(new Set(keys).size).toBe(keys.length)
    for (const key of keys) expect(key).toMatch(/^[a-z]+(-[a-z]+)*$/)
    const names = GENRES.map((def) => def.name)
    expect(new Set(names).size).toBe(names.length)
  })

  it('carries the 24 keys of the contract, in the spec order', () => {
    expect(GENRES.map((def) => def.key)).toEqual([
      'action', 'adventure', 'comedy', 'drama', 'fantasy', 'sci-fi', 'mystery', 'romance', 'horror',
      'thriller', 'psychological', 'supernatural', 'slice-of-life', 'sports', 'mecha', 'music',
      'mahou-shoujo', 'crime', 'documentary', 'family', 'reality', 'war-politics', 'western', 'animation',
    ])
  })

  it('gives every genre at least one catalogue name', () => {
    for (const def of GENRES) expect(def.anilist.length + def.tmdb.length).toBeGreaterThan(0)
  })
})

describe('sourceGenreNames', () => {
  it('maps per scope, TMDB combined genres feeding both halves', () => {
    const action = genreByKey('action')!
    expect(sourceGenreNames(action, 'anilist')).toEqual(['Action'])
    expect(sourceGenreNames(action, 'tmdb')).toEqual(['Action & Adventure'])
    expect(sourceGenreNames(action, null)).toEqual(['Action', 'Action & Adventure'])
    expect(sourceGenreNames(genreByKey('adventure')!, 'tmdb')).toEqual(['Action & Adventure'])
    expect(sourceGenreNames(genreByKey('fantasy')!, 'tmdb')).toEqual(['Sci-Fi & Fantasy'])
    expect(sourceGenreNames(genreByKey('sci-fi')!, 'tmdb')).toEqual(['Sci-Fi & Fantasy'])
    expect(sourceGenreNames(genreByKey('family')!, 'tmdb')).toEqual(['Family', 'Kids'])
  })

  it('is empty where a catalogue has no counterpart', () => {
    expect(sourceGenreNames(genreByKey('romance')!, 'tmdb')).toEqual([])
    expect(sourceGenreNames(genreByKey('romance')!, null)).toEqual(['Romance'])
    expect(sourceGenreNames(genreByKey('crime')!, 'anilist')).toEqual([])
    expect(sourceGenreNames(genreByKey('crime')!, null)).toEqual(['Crime'])
  })

  it('dedupes a name shared by both catalogues on All', () => {
    for (const key of ['comedy', 'drama', 'mystery']) {
      expect(sourceGenreNames(genreByKey(key)!, null)).toEqual([genreByKey(key)!.name])
    }
  })

  it('never maps an excluded genre, in any scope', () => {
    expect([...EXCLUDED_SOURCE_GENRES].sort()).toEqual(['Ecchi', 'Hentai', 'News', 'Soap', 'Talk'])
    for (const def of GENRES) {
      for (const scope of SCOPES) {
        for (const name of sourceGenreNames(def, scope)) expect(EXCLUDED_SOURCE_GENRES.has(name)).toBe(false)
      }
      for (const name of [...def.anilist, ...def.tmdb]) expect(EXCLUDED_SOURCE_GENRES.has(name)).toBe(false)
    }
  })

  it('scopes the genre set: anime-only keys leave TV, TV-only keys leave anime', () => {
    const tv = genresInScope('tmdb').map((def) => def.key)
    const anime = genresInScope('anilist').map((def) => def.key)
    expect(tv).toContain('crime')
    expect(tv).not.toContain('romance')
    expect(anime).toContain('romance')
    expect(anime).not.toContain('crime')
    expect(genresInScope(null)).toHaveLength(GENRES.length)
  })
})

describe('genreByKey', () => {
  it('resolves an exact key', () => {
    expect(genreByKey('slice-of-life')?.name).toBe('Slice of Life')
    expect(genreByKey('war-politics')?.tmdb).toEqual(['War & Politics'])
  })

  it('is null for an unknown key, a display name, a different case or a prototype key', () => {
    for (const key of ['nope', '', 'Action', 'ACTION', 'Slice of Life', 'ecchi', 'hentai', 'constructor', '__proto__', 'toString']) {
      expect(genreByKey(key)).toBeNull()
    }
  })
})

describe('buildGenreTiles / rankGenreTiles', () => {
  const portraits = new Map<string, string | null>([
    ['a', 'https://img/a.jpg'],
    ['b', null],
    ['c', 'https://img/c.jpg'],
    ['d', 'https://img/d.jpg'],
    ['e', 'https://img/a.jpg'], // the same art on two franchises
    ['f', 'https://img/f.jpg'],
    ['g', 'https://img/g.jpg'],
  ])

  it('fills a collage with up to four distinct portraits in rank order, skipping art-less titles', () => {
    const tiles = buildGenreTiles(
      'anilist',
      new Map([['action', 7]]),
      new Map([['action', ['a', 'b', 'c', 'e', 'd', 'f', 'g']]]),
      portraits,
    )
    const action = tiles.find((tile) => tile.key === 'action')!
    expect(action).toEqual({
      key: 'action',
      name: 'Action',
      count: 7,
      posters: ['https://img/a.jpg', 'https://img/c.jpg', 'https://img/d.jpg', 'https://img/f.jpg'],
    })
  })

  it('emits every in-scope genre (zero counts included) and nothing out of scope', () => {
    const tiles = buildGenreTiles('tmdb', new Map(), new Map(), portraits)
    expect(tiles.map((tile) => tile.key)).toEqual(genresInScope('tmdb').map((def) => def.key))
    expect(tiles.every((tile) => tile.count === 0 && tile.posters.length === 0)).toBe(true)
  })

  it('keeps count >= 3, orders by count desc then key', () => {
    const tile = (key: string, count: number): DiscoverGenre => ({ key, name: key, count, posters: [] })
    const ranked = rankGenreTiles([tile('drama', 3), tile('action', 10), tile('comedy', 10), tile('horror', 2), tile('mecha', 0)])
    expect(ranked.map((t) => `${t.key}:${t.count}`)).toEqual(['action:10', 'comedy:10', 'drama:3'])
  })
})

describe('genre page cursor', () => {
  it('round-trips an offset and is opaque base64url', () => {
    for (const offset of [0, 24, 48, 9_999, MAX_GENRE_OFFSET]) {
      const cursor = encodeGenreCursor(offset)
      expect(cursor).toMatch(/^[A-Za-z0-9_-]+$/)
      expect(decodeGenreCursor(cursor)).toBe(offset)
    }
  })

  it('rejects anything this server did not write', () => {
    const enc = (value: unknown) => Buffer.from(JSON.stringify(value), 'utf8').toString('base64url')
    for (const bad of [
      '',
      'not base64!',
      'eyJvIjo1fQ==', // padding is not base64url
      Buffer.from('{not json', 'utf8').toString('base64url'),
      enc({ o: -1 }),
      enc({ o: 2.5 }),
      enc({ o: '24' }),
      enc({ o: MAX_GENRE_OFFSET + 1 }),
      enc({ o: 24, extra: 1 }),
      enc({ offset: 24 }),
      enc([24]),
      enc(null),
      enc(24),
      'A'.repeat(200),
    ]) {
      expect(decodeGenreCursor(bad)).toBeNull()
    }
  })
})
