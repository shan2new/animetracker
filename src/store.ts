import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import type { LibraryEntry, WatchStatus } from './types'

const LIB_KEY = 'anitrack.library.v1'
const OPENED_KEY = 'anitrack.lastOpenedAt.v1'
const VALID_STATUS: WatchStatus[] = ['watching', 'completed', 'planned']

// localStorage can throw on *access* (private mode, disabled storage, SecurityError),
// not just read/write — so every touch goes through these guards.
function safeGet(key: string): string | null {
  try {
    return localStorage.getItem(key)
  } catch {
    return null
  }
}
function safeSet(key: string, value: string): void {
  try {
    localStorage.setItem(key, value)
  } catch {
    /* storage unavailable or quota exceeded — operate in-memory only */
  }
}

// Coerce a persisted value into a clean LibraryEntry, or drop it. Defends against
// schema drift, hand-edits, and corrupt data producing NaN progress downstream.
function sanitize(raw: unknown): LibraryEntry | null {
  if (!raw || typeof raw !== 'object') return null
  const e = raw as Record<string, unknown>
  const id = Number(e.id)
  if (!Number.isFinite(id)) return null
  const progress = Number(e.progress)
  const status = VALID_STATUS.includes(e.status as WatchStatus) ? (e.status as WatchStatus) : 'planned'
  const addedAt = Number(e.addedAt)
  return {
    id,
    status,
    progress: Number.isFinite(progress) ? Math.max(0, Math.floor(progress)) : 0,
    addedAt: Number.isFinite(addedAt) ? addedAt : 0,
  }
}

// The library starts empty — add shows from the Add tab. Persisted in localStorage.
function load(): LibraryEntry[] {
  try {
    const raw = safeGet(LIB_KEY)
    if (!raw) return []
    const parsed = JSON.parse(raw)
    if (!Array.isArray(parsed)) return []
    // Drop dupes by id and any unusable entries.
    const seen = new Set<number>()
    const out: LibraryEntry[] = []
    for (const item of parsed) {
      const entry = sanitize(item)
      if (entry && !seen.has(entry.id)) {
        seen.add(entry.id)
        out.push(entry)
      }
    }
    return out
  } catch {
    return []
  }
}

export interface LibraryApi {
  library: LibraryEntry[]
  /** When the app was last opened, before this session — drives "since you were last here". */
  prevOpenedAt: number
  has: (id: number) => boolean
  add: (id: number, status?: WatchStatus) => void
  remove: (id: number) => void
  setStatus: (id: number, status: WatchStatus) => void
  setProgress: (id: number, progress: number) => void
}

export function useLibrary(): LibraryApi {
  const [library, setLibrary] = useState<LibraryEntry[]>(load)

  // Capture the previous open time once, then stamp "now" for next launch.
  const prevOpenedAt = useRef<number>(Number(safeGet(OPENED_KEY)) || 0)
  useEffect(() => {
    safeSet(OPENED_KEY, String(Date.now()))
  }, [])

  useEffect(() => {
    safeSet(LIB_KEY, JSON.stringify(library))
  }, [library])

  // A ref mirror lets `has` stay referentially stable (no `library` dep), so the
  // returned API object only changes when the library actually changes.
  const libRef = useRef(library)
  libRef.current = library

  const has = useCallback((id: number) => libRef.current.some((e) => e.id === id), [])

  const add = useCallback((id: number, status: WatchStatus = 'planned') => {
    setLibrary((lib) =>
      lib.some((e) => e.id === id) ? lib : [...lib, { id, status, progress: 0, addedAt: Date.now() }],
    )
  }, [])

  const remove = useCallback((id: number) => {
    setLibrary((lib) => lib.filter((e) => e.id !== id))
  }, [])

  const setStatus = useCallback((id: number, status: WatchStatus) => {
    setLibrary((lib) => lib.map((e) => (e.id === id ? { ...e, status } : e)))
  }, [])

  const setProgress = useCallback((id: number, progress: number) => {
    const next = Number.isFinite(progress) ? Math.max(0, Math.floor(progress)) : 0
    setLibrary((lib) => lib.map((e) => (e.id === id ? { ...e, progress: next } : e)))
  }, [])

  return useMemo(
    () => ({ library, prevOpenedAt: prevOpenedAt.current, has, add, remove, setStatus, setProgress }),
    [library, has, add, remove, setStatus, setProgress],
  )
}
