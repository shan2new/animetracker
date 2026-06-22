import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import type { MouseEvent, ReactNode } from 'react'
import { fetchByIds, fetchLastAired, searchMedia } from './anilist'
import {
  D,
  H,
  episodesBehind,
  fmtAgo,
  fmtCountdown,
  fmtDay,
  fmtMonthDay,
  fmtTime,
  fmtTodayDate,
  greetingFor,
  istDayKey,
  istMondayCol,
  toShow,
  weekdayNameMonFirst,
} from './format'
import { useLibrary } from './store'
import type { AniListMedia, Show, WatchStatus } from './types'

const ACCENT = '#F0A24E'
const SOON_WINDOW = 48 * H // "Airing soon" lookahead
const IMMINENT_WINDOW = 24 * H // countdown turns accent when this close
const NEW_LOOKBACK = 3 * D // default "out now" window before any prior open
const CLOCK_TICK = 20_000 // countdowns/relative times only change at minute granularity
const UNDO_MS = 5000 // how long the undo toast stays
const REFRESH_MS = 5 * 60_000 // background re-fetch of live airing data while visible

type Screen = 'home' | 'schedule' | 'library' | 'search'
type HomeLayout = 'briefing' | 'spotlight' | 'grid'
type GroupKey = 'behind' | 'caughtup' | 'finished' | 'planned'
type LibFilter = 'all' | GroupKey
type CardAction = 'mark' | 'add' | 'none'

// Library buckets: section header label, chip label, and the card action they use.
// Drives both the chip row and the grouped rendering from one source of truth.
const LIB_GROUPS: { key: GroupKey; label: string; chip: string; action: CardAction }[] = [
  { key: 'behind', label: 'Behind', chip: 'Behind', action: 'mark' },
  { key: 'caughtup', label: 'Caught up', chip: 'Caught up', action: 'none' },
  { key: 'finished', label: 'Finished airing', chip: 'Finished', action: 'none' },
  { key: 'planned', label: 'Plan to watch', chip: 'Plan to watch', action: 'none' },
]

interface Undo {
  id: number
  prev: number
  title: string
  ep: number
  added?: boolean
  statusLabel?: string
}

// ---------- Icons ----------
const Check = ({ size = 17, w = 2.7, stroke = '#0B0B0E' }: { size?: number; w?: number; stroke?: string }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={stroke} strokeWidth={w} strokeLinecap="round" strokeLinejoin="round">
    <path d="M5 13l4 4L19 7" />
  </svg>
)

const Plus = ({ size = 19, w = 2.4, stroke = '#0B0B0E' }: { size?: number; w?: number; stroke?: string }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={stroke} strokeWidth={w} strokeLinecap="round" strokeLinejoin="round">
    <path d="M12 5v14M5 12h14" />
  </svg>
)

// Banner image (or gradient fallback) used by the hero card and detail sheet.
function BannerImg({ src, opacity }: { src: string; opacity: number }) {
  return src ? (
    <div style={{ width: '100%', height: '100%', backgroundImage: `url(${src})`, backgroundSize: 'cover', backgroundPosition: 'center', opacity }} />
  ) : (
    <div style={{ width: '100%', height: '100%', background: 'linear-gradient(150deg,#27272f,#141418)' }} />
  )
}

// The shared "just caught up" celebration overlay.
function CaughtUpOverlay({ size = 50 }: { size?: number }) {
  return (
    <div style={{ position: 'absolute', inset: 0, display: 'flex', alignItems: 'center', justifyContent: 'center', background: 'rgba(11,11,14,0.7)', backdropFilter: 'blur(3px)', animation: 'at-ccfade .25s ease', zIndex: 6 }}>
      <div style={{ position: 'relative', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
        <div style={{ position: 'absolute', width: size + 10, height: size + 10, borderRadius: '50%', border: `2px solid ${ACCENT}`, animation: 'at-ccring .75s ease-out forwards' }} />
        <div style={{ width: size, height: size, borderRadius: '50%', background: ACCENT, display: 'flex', alignItems: 'center', justifyContent: 'center', animation: 'at-ccpop .42s cubic-bezier(.2,1.25,.4,1) both', boxShadow: '0 0 30px rgba(240,162,78,0.7)' }}>
          <svg width={size * 0.52} height={size * 0.52} viewBox="0 0 24 24" fill="none" stroke="#0B0B0E" strokeWidth={3} strokeLinecap="round" strokeLinejoin="round">
            <path d="M5 13l4 4L19 7" strokeDasharray="24" strokeDashoffset="24" style={{ animation: 'at-ccdraw .4s .12s ease-out forwards' }} />
          </svg>
        </div>
      </div>
    </div>
  )
}

// ---------- Card view-model ----------
interface CardVM {
  id: number
  title: string
  cover: string
  hasCover: boolean
  isBehind: boolean
  behindLabel: string
  caughtUp: boolean
  showProgress: boolean
  progressLabel: string
  progressPct: string
  actionMark: boolean
  actionAdd: boolean
  owned: boolean
  justCaughtUp: boolean
  airedEpisodes: number
  airedAgo: string
  nextEp: number | null
  countdown: string
  countdownColor: string
  airTime: string
  dayLabel: string
  banner: string
}

function cardVM(s: Show, action: CardAction, justCaught: number[], now: number, owned = false): CardVM {
  const bh = episodesBehind(s)
  return {
    id: s.id,
    title: s.title,
    cover: s.cover,
    hasCover: !!s.cover,
    isBehind: bh > 0,
    behindLabel: bh > 0 ? `${bh} behind` : '',
    caughtUp: s.isReleasing && bh === 0,
    showProgress: s.totalEpisodes > 0 && action !== 'add',
    progressLabel: `${s.progress} / ${s.totalEpisodes || '?'}`,
    progressPct: (s.totalEpisodes ? Math.min(100, Math.round((100 * s.progress) / s.totalEpisodes)) : 0) + '%',
    actionMark: action === 'mark' && bh > 0,
    actionAdd: action === 'add',
    owned,
    justCaughtUp: justCaught.includes(s.id),
    airedEpisodes: s.airedEpisodes,
    airedAgo: s.lastAiredAt ? fmtAgo(s.lastAiredAt, now) : '',
    nextEp: s.nextEpisodeNumber,
    countdown: s.nextAiringAt ? fmtCountdown(s.nextAiringAt, now) : '',
    countdownColor: s.nextAiringAt && s.nextAiringAt - now <= IMMINENT_WINDOW ? ACCENT : 'rgba(245,245,247,0.7)',
    airTime: s.nextAiringAt ? fmtTime(s.nextAiringAt) : '',
    dayLabel: s.nextAiringAt ? fmtDay(s.nextAiringAt, now) : '',
    banner: s.banner || s.cover,
  }
}

// ---------- Poster card (ShowCard.dc.html) ----------
function ShowCard({ vm, onPrimary, onOpen }: { vm: CardVM; onPrimary: (e: MouseEvent) => void; onOpen: () => void }) {
  return (
    <div onClick={onOpen} style={{ position: 'relative', borderRadius: 15, overflow: 'hidden', background: '#16161B', border: '1px solid rgba(255,255,255,0.06)', cursor: 'pointer' }}>
      <div style={{ position: 'relative', aspectRatio: '2 / 3', background: '#16161B' }}>
        {vm.hasCover ? (
          <div style={{ position: 'absolute', inset: 0, backgroundImage: `url(${vm.cover})`, backgroundSize: 'cover', backgroundPosition: 'center' }} />
        ) : (
          <div style={{ position: 'absolute', inset: 0, background: 'linear-gradient(155deg,#27272f,#141418)', display: 'flex', alignItems: 'flex-end', padding: 11, fontSize: 12.5, fontWeight: 600, color: 'rgba(255,255,255,0.55)', lineHeight: 1.2 }}>{vm.title}</div>
        )}
        <div style={{ position: 'absolute', inset: 0, background: 'linear-gradient(0deg,rgba(11,11,14,0.94) 4%,rgba(11,11,14,0.2) 44%,transparent 68%)' }} />

        {vm.isBehind && (
          <div style={{ position: 'absolute', top: 9, left: 9, padding: '4px 9px', borderRadius: 8, background: ACCENT, fontSize: 11, fontWeight: 600, color: '#0B0B0E', whiteSpace: 'nowrap', boxShadow: '0 2px 8px rgba(0,0,0,0.35)' }}>{vm.behindLabel}</div>
        )}
        {vm.caughtUp && (
          <div style={{ position: 'absolute', top: 9, left: 9, display: 'flex', alignItems: 'center', gap: 4, padding: '4px 8px 4px 7px', borderRadius: 8, background: 'rgba(11,11,14,0.55)', backdropFilter: 'blur(8px)', fontSize: 11, fontWeight: 500, color: ACCENT }}>
            <Check size={11} w={3.2} stroke={ACCENT} />Caught up
          </div>
        )}

        {vm.actionMark && (
          <button onClick={onPrimary} aria-label="Mark caught up" className="at-btn-primary" style={{ position: 'absolute', top: 8, right: 8, width: 40, height: 40, border: 'none', borderRadius: '50%', cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', background: ACCENT, boxShadow: '0 4px 16px rgba(240,162,78,0.45),0 0 0 3px rgba(11,11,14,0.45)' }}>
            <Check size={20} />
          </button>
        )}
        {vm.actionAdd && !vm.owned && (
          <button onClick={onPrimary} aria-label="Add to library" className="at-btn-primary" style={{ position: 'absolute', top: 8, right: 8, width: 40, height: 40, border: 'none', borderRadius: '50%', cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', background: 'rgba(11,11,14,0.6)', backdropFilter: 'blur(8px)', boxShadow: '0 0 0 1px rgba(255,255,255,0.16)' }}>
            <Plus size={19} stroke="#F5F5F7" />
          </button>
        )}
        {vm.actionAdd && vm.owned && (
          <div aria-label="In library" style={{ position: 'absolute', top: 8, right: 8, display: 'flex', alignItems: 'center', gap: 4, padding: '5px 9px 5px 7px', borderRadius: 20, background: 'rgba(11,11,14,0.6)', backdropFilter: 'blur(8px)', boxShadow: '0 0 0 1px rgba(240,162,78,0.4)', fontSize: 10.5, fontWeight: 600, color: ACCENT }}>
            <Check size={11} w={3.2} stroke={ACCENT} />In library
          </div>
        )}

        <div style={{ position: 'absolute', left: 0, right: 0, bottom: 0, padding: '11px 12px' }}>
          <div style={{ fontSize: 14, fontWeight: 600, letterSpacing: '-0.015em', lineHeight: 1.2, overflow: 'hidden', display: '-webkit-box', WebkitLineClamp: 2, WebkitBoxOrient: 'vertical' }}>{vm.title}</div>
          {vm.showProgress && (
            <div style={{ marginTop: 8 }}>
              <div style={{ fontSize: 11, fontFamily: "'Geist Mono',monospace", color: 'rgba(245,245,247,0.62)', marginBottom: 5 }}>{vm.progressLabel}</div>
              <div style={{ height: 3, borderRadius: 3, background: 'rgba(255,255,255,0.16)', overflow: 'hidden' }}>
                <div style={{ height: '100%', borderRadius: 3, background: ACCENT, width: vm.progressPct }} />
              </div>
            </div>
          )}
        </div>

        {vm.justCaughtUp && <CaughtUpOverlay size={52} />}
      </div>
    </div>
  )
}

// ---------- Section header ----------
function SectionHead({ dot, icon, label, trailing }: { dot?: boolean; icon?: ReactNode; label: string; trailing?: string }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 9, marginBottom: 14 }}>
      {dot && <span style={{ width: 7, height: 7, borderRadius: '50%', background: ACCENT, boxShadow: '0 0 10px rgba(240,162,78,0.85)' }} />}
      {icon}
      <h2 style={{ margin: 0, fontSize: 12.5, fontWeight: 600, letterSpacing: '0.07em', textTransform: 'uppercase', color: 'rgba(245,245,247,0.72)' }}>{label}</h2>
      {trailing && <span style={{ fontSize: 11.5, color: 'rgba(245,245,247,0.4)', marginLeft: 'auto', whiteSpace: 'nowrap' }}>{trailing}</span>}
    </div>
  )
}

// ============================================================
export default function App() {
  const lib = useLibrary()
  const [media, setMedia] = useState<Record<number, AniListMedia>>({})
  const [lastAired, setLastAired] = useState<Record<number, number>>({})
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(false)
  const [refreshTick, setRefreshTick] = useState(0)
  const [now, setNow] = useState(() => Date.now())

  const [screen, setScreen] = useState<Screen>('home')
  const [homeLayout, setHomeLayout] = useState<HomeLayout>('briefing')
  const [libFilter, setLibFilter] = useState<LibFilter>('all')
  const [libQuery, setLibQuery] = useState('')
  const [searchQuery, setSearchQuery] = useState('')
  const [searchResults, setSearchResults] = useState<AniListMedia[]>([])
  const [searchBusy, setSearchBusy] = useState(false)
  const [searchError, setSearchError] = useState(false)
  const [detailId, setDetailId] = useState<number | null>(null)

  const [justCaught, setJustCaught] = useState<number[]>([])
  const [undo, setUndo] = useState<Undo | null>(null)
  const ccTimers = useRef<Map<number, number>>(new Map())
  const undoTimer = useRef<number | undefined>(undefined)

  const mergeMedia = useCallback((items: AniListMedia[]) => {
    if (items.length === 0) return
    setMedia((m) => {
      const next = { ...m }
      for (const it of items) next[it.id] = it
      return next
    })
  }, [])

  // Tick the clock for live countdowns (nothing sub-minute is displayed).
  useEffect(() => {
    const t = window.setInterval(() => setNow(Date.now()), CLOCK_TICK)
    return () => window.clearInterval(t)
  }, [])

  // Fetch live AniList metadata when the set of library ids changes, and on each refresh tick.
  const idsKey = useMemo(() => [...lib.library.map((e) => e.id)].sort((a, b) => a - b).join(','), [lib.library])
  useEffect(() => {
    let cancelled = false
    const ids = idsKey ? idsKey.split(',').map(Number) : []
    if (ids.length === 0) {
      setLoading(false)
      setError(false)
      return
    }
    setLoading(true)
    fetchByIds(ids)
      .then(async (items) => {
        if (cancelled) return
        setError(false)
        mergeMedia(items)
        // For airing shows, pull the exact previous airing time from AniList (best-effort).
        const releasingIds = items.filter((m) => m.status === 'RELEASING').map((m) => m.id)
        const exact = await fetchLastAired(releasingIds)
        if (!cancelled) setLastAired((prev) => ({ ...prev, ...exact }))
      })
      .catch(() => {
        if (!cancelled) setError(true)
      })
      .finally(() => {
        if (!cancelled) setLoading(false)
      })
    return () => {
      cancelled = true
    }
  }, [idsKey, mergeMedia, refreshTick])

  // Keep live airing data fresh: refetch when the tab regains focus and on a slow interval.
  useEffect(() => {
    const refresh = () => {
      if (document.visibilityState === 'visible') setRefreshTick((t) => t + 1)
    }
    window.addEventListener('focus', refresh)
    document.addEventListener('visibilitychange', refresh)
    const iv = window.setInterval(refresh, REFRESH_MS)
    return () => {
      window.removeEventListener('focus', refresh)
      document.removeEventListener('visibilitychange', refresh)
      window.clearInterval(iv)
    }
  }, [])

  // Debounced AniList search for the Add tab. Only shows "Searching…" for typed queries.
  useEffect(() => {
    let cancelled = false
    const trimmed = searchQuery.trim()
    const t = window.setTimeout(() => {
      if (trimmed) setSearchBusy(true)
      searchMedia(searchQuery)
        .then((items) => {
          if (cancelled) return
          setSearchError(false)
          mergeMedia(items)
          setSearchResults(items)
        })
        .catch(() => {
          if (!cancelled) setSearchError(true)
        })
        .finally(() => {
          if (!cancelled) setSearchBusy(false)
        })
    }, trimmed ? 320 : 0)
    return () => {
      cancelled = true
      window.clearTimeout(t)
    }
  }, [searchQuery, mergeMedia])

  // Clear any pending timers on unmount.
  const ccTimersRef = ccTimers
  useEffect(() => {
    return () => {
      ccTimersRef.current.forEach((t) => window.clearTimeout(t))
      window.clearTimeout(undoTimer.current)
    }
  }, [ccTimersRef])

  // Build live Shows from the library + fetched metadata.
  const shows = useMemo<Show[]>(
    () => lib.library.map((e) => toShow(e, media[e.id], lastAired[e.id])),
    [lib.library, media, lastAired],
  )
  const showById = useMemo(() => new Map(shows.map((s) => [s.id, s])), [shows])

  // ---------- Actions ----------
  const go = (s: Screen) => {
    setScreen(s)
    setDetailId(null)
  }

  // Close via the browser history entry pushed on open, so the hardware/browser back
  // button also dismisses the sheet. Falls back to a direct close if no entry exists.
  const closeDetail = useCallback(() => {
    if (window.history.state?.sheet) window.history.back()
    else setDetailId(null)
  }, [])

  useEffect(() => {
    if (detailId == null) return
    window.history.pushState({ sheet: true }, '')
    const onPop = () => setDetailId(null)
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') closeDetail()
    }
    window.addEventListener('popstate', onPop)
    window.addEventListener('keydown', onKey)
    return () => {
      window.removeEventListener('popstate', onPop)
      window.removeEventListener('keydown', onKey)
    }
  }, [detailId, closeDetail])

  const markCaughtUp = useCallback(
    (id: number) => {
      const s = showById.get(id)
      if (!s) return
      lib.setProgress(id, s.airedEpisodes)
      // Keep the original `prev` if an undo for this show is already pending, so a
      // double-mark still restores the true starting episode.
      setUndo((prev) =>
        prev && !prev.added && prev.id === id
          ? { ...prev, ep: s.airedEpisodes }
          : { id, prev: s.progress, title: s.title, ep: s.airedEpisodes },
      )
      setJustCaught((j) => (j.includes(id) ? j : [...j, id]))
      // Per-id celebration timer so rapid marks don't cancel each other's overlays.
      const existing = ccTimers.current.get(id)
      if (existing) window.clearTimeout(existing)
      ccTimers.current.set(
        id,
        window.setTimeout(() => {
          setJustCaught((j) => j.filter((x) => x !== id))
          ccTimers.current.delete(id)
        }, 1300),
      )
      window.clearTimeout(undoTimer.current)
      undoTimer.current = window.setTimeout(() => setUndo(null), UNDO_MS)
    },
    [lib, showById],
  )

  const addToLibrary = useCallback(
    (id: number) => {
      if (lib.has(id)) return
      const m = media[id]
      // A currently-airing show you add is almost certainly something you're watching.
      const status: WatchStatus = m?.status === 'RELEASING' ? 'watching' : 'planned'
      const statusLabel = status === 'watching' ? 'Watching' : 'Plan to watch'
      lib.add(id, status)
      setUndo({ id, prev: 0, title: m?.title.english || m?.title.romaji || 'Anime', ep: 0, added: true, statusLabel })
      window.clearTimeout(undoTimer.current)
      undoTimer.current = window.setTimeout(() => setUndo(null), UNDO_MS)
    },
    [lib, media],
  )

  const doUndo = useCallback(() => {
    if (!undo) return
    if (undo.added) {
      lib.remove(undo.id)
    } else if (lib.has(undo.id)) {
      lib.setProgress(undo.id, undo.prev)
      setJustCaught((j) => j.filter((x) => x !== undo.id))
    }
    setUndo(null)
    window.clearTimeout(undoTimer.current)
  }, [undo, lib])

  // ============================================================
  // Derived view data (ported from the design's renderVals)
  // ============================================================
  const libraryEmpty = lib.library.length === 0
  const airing = shows.filter((s) => s.isReleasing)

  // "Out now" — episodes that aired since the user was last here.
  const effectivePrev = lib.prevOpenedAt || now - NEW_LOOKBACK
  const outNowShows = airing.filter((s) => s.lastAiredAt != null && s.lastAiredAt > effectivePrev)
  const outNow = outNowShows.map((s) => cardVM(s, 'mark', justCaught, now))
  const newEps = outNowShows.length

  const soonShows = airing
    .filter((s) => s.nextAiringAt != null && s.nextAiringAt - now > 0 && s.nextAiringAt - now <= SOON_WINDOW)
    .sort((a, b) => (a.nextAiringAt! - b.nextAiringAt!))
  const soon = soonShows.map((s) => cardVM(s, 'none', justCaught, now))

  const hero = outNow[0]
  const spotRest = outNow.slice(1)

  // Greeting / header (IST)
  const greeting = greetingFor(now)
  const todayDate = fmtTodayDate(now)
  const homeSubtitle =
    newEps > 0
      ? `You have ${newEps} fresh ${newEps === 1 ? 'episode' : 'episodes'} waiting since you were last here.`
      : 'Nothing new has aired. You’re all caught up.'
  const droppedSummary = newEps > 0 ? `${newEps} ${newEps === 1 ? 'show' : 'shows'}` : ''
  // Soonest upcoming episode across ALL airing shows (not just the 48h window).
  const nextUp = airing
    .filter((s) => s.nextAiringAt != null && s.nextAiringAt > now)
    .sort((a, b) => a.nextAiringAt! - b.nextAiringAt!)[0]
  const nextDropLabel = nextUp ? `${fmtDay(nextUp.nextAiringAt!, now)} ${fmtTime(nextUp.nextAiringAt!)}` : null

  // Schedule — this week's 7 columns (Mon..Sun), matching each show to the ACTUAL
  // calendar day its next episode airs (not just the weekday), so far-future episodes
  // don't masquerade as airing this week.
  const todayCol = istMondayCol(now)
  const scheduleDays = Array.from({ length: 7 }, (_, c) => {
    const colDate = now + (c - todayCol) * D
    const colKey = istDayKey(colDate)
    const ds = airing
      .filter((s) => s.nextAiringAt != null && istDayKey(s.nextAiringAt) === colKey)
      .sort((a, b) => a.nextAiringAt! - b.nextAiringAt!)
    return {
      label: weekdayNameMonFirst(c),
      isToday: c === todayCol,
      dateLabel: fmtMonthDay(colDate),
      shows: ds.map((s) => cardVM(s, 'none', justCaught, now)),
    }
  })

  // Library groups — classify each show into exactly one bucket, then filter by the active chip.
  const ql = libQuery.toLowerCase()
  const inLib = shows.filter((s) => !ql || s.title.toLowerCase().includes(ql))
  const bucketOf = (s: Show): GroupKey => {
    if (s.status === 'planned') return 'planned'
    if (s.status === 'watching' && s.isReleasing) return episodesBehind(s) > 0 ? 'behind' : 'caughtup'
    return 'finished'
  }
  const libGroups = LIB_GROUPS.filter((g) => libFilter === 'all' || libFilter === g.key)
    .map((g) => {
      const arr = inLib.filter((s) => bucketOf(s) === g.key)
      return { label: g.label, count: String(arr.length), cards: arr.map((s) => cardVM(s, g.action, justCaught, now)) }
    })
    .filter((g) => g.cards.length > 0)

  const filterChips: { key: LibFilter; label: string }[] = [
    { key: 'all', label: 'All' },
    ...LIB_GROUPS.map((g) => ({ key: g.key as LibFilter, label: g.chip })),
  ]

  // Search results — keep items already in the library, shown with an "In library" marker.
  const searchShows = searchResults.map((m) =>
    toShow({ id: m.id, status: 'planned', progress: 0, addedAt: 0 }, m, lastAired[m.id]),
  )
  const searchHint = searchBusy
    ? 'Searching…'
    : searchError
      ? 'Couldn’t reach AniList — check your connection.'
      : searchQuery.trim()
        ? `${searchShows.length} result${searchShows.length === 1 ? '' : 's'}`
        : 'Trending on AniList'

  // Detail (resolves from library or current search results)
  const detailShow: Show | null =
    detailId == null ? null : showById.get(detailId) ?? searchShows.find((s) => s.id === detailId) ?? null
  const detailInLib = detailShow ? lib.has(detailShow.id) : false

  const homeEmpty = outNow.length === 0 && soon.length === 0

  // ---------- shared style helpers ----------
  const navColor = (k: Screen) => (screen === k ? ACCENT : 'rgba(245,245,247,0.45)')

  return (
    <div className="at-shell">
      <div className="at-app">
        {/* ===== SCROLL CONTENT ===== */}
        <div className="at-scroll" style={{ flex: 1, overflowY: 'auto', overflowX: 'hidden', WebkitOverflowScrolling: 'touch' }}>
          {/* ========== HOME ========== */}
          {screen === 'home' && (
            <div style={{ padding: '34px 20px 28px', animation: 'at-fadein .4s ease' }}>
              <div style={{ fontSize: 12.5, fontWeight: 500, letterSpacing: '0.02em', color: ACCENT, fontFamily: "'Geist Mono',monospace" }}>{todayDate}</div>
              <h1 style={{ margin: '7px 0 0', fontSize: 29, fontWeight: 600, letterSpacing: '-0.035em', lineHeight: 1.08 }}>{greeting}</h1>
              <p style={{ margin: '9px 0 0', fontSize: 14.5, color: 'rgba(245,245,247,0.52)', lineHeight: 1.45 }}>
                {libraryEmpty ? 'Track what’s airing — add your first show to get started.' : homeSubtitle}
              </p>

              {error && !libraryEmpty && <RetryBanner onRetry={() => setRefreshTick((t) => t + 1)} />}

              {/* layout toggle — only meaningful when there are "out now" cards to lay out */}
              {outNow.length > 0 && (
                <div role="tablist" aria-label="Home layout" style={{ display: 'flex', gap: 3, marginTop: 18, padding: 4, borderRadius: 13, background: 'rgba(255,255,255,0.04)', border: '1px solid rgba(255,255,255,0.06)' }}>
                  {(['briefing', 'spotlight', 'grid'] as HomeLayout[]).map((k) => (
                    <button
                      key={k}
                      role="tab"
                      aria-selected={homeLayout === k}
                      onClick={() => setHomeLayout(k)}
                      style={{ flex: 1, padding: '8px 0', border: 'none', borderRadius: 9, cursor: 'pointer', fontSize: 12.5, fontWeight: 500, textTransform: 'capitalize', color: homeLayout === k ? '#0B0B0E' : 'rgba(245,245,247,0.55)', background: homeLayout === k ? ACCENT : 'transparent', transition: 'all .18s' }}
                    >
                      {k}
                    </button>
                  ))}
                </div>
              )}

              {loading && shows.length === 0 && <Loader />}

              {libraryEmpty && !loading && (
                <EmptyState
                  title="Welcome to AniTrack"
                  body="Your airing-first tracker. Add shows you’re watching and we’ll tell you exactly what dropped and what’s next."
                  ctaLabel="Add your first show"
                  onCta={() => go('search')}
                />
              )}

              {!libraryEmpty && homeEmpty && !loading && (
                <EmptyState
                  title="You're all caught up"
                  body={nextDropLabel ? `Nothing new since you were last here. Your next episode lands ${nextDropLabel}.` : 'Nothing new since you were last here.'}
                />
              )}

              {outNow.length > 0 && (
                <div style={{ marginTop: 32 }}>
                  <SectionHead dot label="Out now" trailing={droppedSummary} />

                  {homeLayout === 'briefing' && (
                    <div style={{ display: 'flex', flexDirection: 'column', gap: 11 }}>
                      {outNow.map((c) => (
                        <BriefingRow key={c.id} vm={c} onOpen={() => setDetailId(c.id)} onPrimary={() => markCaughtUp(c.id)} />
                      ))}
                    </div>
                  )}

                  {homeLayout === 'spotlight' && (
                    <div>
                      {hero && <HeroCard vm={hero} onOpen={() => setDetailId(hero.id)} onPrimary={() => markCaughtUp(hero.id)} />}
                      {spotRest.length > 0 && (
                        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 13, marginTop: 13 }}>
                          {spotRest.map((c) => (
                            <ShowCard key={c.id} vm={c} onOpen={() => setDetailId(c.id)} onPrimary={(e) => { e.stopPropagation(); markCaughtUp(c.id) }} />
                          ))}
                        </div>
                      )}
                    </div>
                  )}

                  {homeLayout === 'grid' && (
                    <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 13 }}>
                      {outNow.map((c) => (
                        <ShowCard key={c.id} vm={c} onOpen={() => setDetailId(c.id)} onPrimary={(e) => { e.stopPropagation(); markCaughtUp(c.id) }} />
                      ))}
                    </div>
                  )}
                </div>
              )}

              {soon.length > 0 && (
                <div style={{ marginTop: 34 }}>
                  <SectionHead icon={<ClockIcon />} label="Airing soon" trailing="next 48h" />
                  <div style={{ borderRadius: 16, border: '1px solid rgba(255,255,255,0.06)', overflow: 'hidden', background: 'rgba(255,255,255,0.018)' }}>
                    {soon.map((c) => (
                      <div key={c.id} onClick={() => setDetailId(c.id)} style={{ display: 'flex', alignItems: 'center', gap: 13, padding: '12px 14px', borderBottom: '1px solid rgba(255,255,255,0.05)', cursor: 'pointer' }}>
                        <Thumb cover={c.cover} hasCover={c.hasCover} w={34} h={48} r={7} />
                        <div style={{ flex: 1, minWidth: 0 }}>
                          <div style={{ fontSize: 14.5, fontWeight: 500, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{c.title}</div>
                          <div style={{ fontSize: 12, color: 'rgba(245,245,247,0.44)', marginTop: 2 }}>Ep {c.nextEp} · {c.dayLabel} {c.airTime}</div>
                        </div>
                        <div style={{ fontFamily: "'Geist Mono',monospace", fontSize: 14, fontWeight: 500, color: c.countdownColor }}>{c.countdown}</div>
                      </div>
                    ))}
                  </div>
                </div>
              )}
            </div>
          )}

          {/* ========== SCHEDULE ========== */}
          {screen === 'schedule' && (
            <div style={{ padding: '34px 20px 28px', animation: 'at-fadein .4s ease' }}>
              <h1 style={{ margin: 0, fontSize: 27, fontWeight: 600, letterSpacing: '-0.03em' }}>Schedule</h1>
              <p style={{ margin: '8px 0 0', fontSize: 14, color: 'rgba(245,245,247,0.52)', lineHeight: 1.45 }}>Your week of airings, in IST. Today is highlighted.</p>
              {error && <RetryBanner onRetry={() => setRefreshTick((t) => t + 1)} />}
              {loading && shows.length === 0 && <Loader />}
              {!loading && airing.length === 0 ? (
                <EmptyState
                  title="No airing shows yet"
                  body={libraryEmpty ? 'Add currently-airing anime and your weekly schedule fills in here.' : 'None of your shows are currently airing. Add airing anime to see them here.'}
                  ctaLabel="Add anime"
                  onCta={() => go('search')}
                />
              ) : (
              <div style={{ marginTop: 26 }}>
                {scheduleDays.map((day) => (
                  <div key={day.label} style={{ marginBottom: 24 }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: 9, paddingBottom: 11, borderBottom: '1px solid rgba(255,255,255,0.07)' }}>
                      {day.isToday && <span style={{ width: 7, height: 7, borderRadius: '50%', background: ACCENT, boxShadow: '0 0 9px rgba(240,162,78,0.85)' }} />}
                      <span style={{ fontSize: 16, fontWeight: 600, letterSpacing: '-0.02em', color: day.isToday ? ACCENT : '#F5F5F7' }}>{day.label}</span>
                      <span style={{ fontSize: 13, color: 'rgba(245,245,247,0.36)', fontFamily: "'Geist Mono',monospace" }}>{day.dateLabel}</span>
                      {day.isToday && <span style={{ marginLeft: 'auto', fontSize: 10, fontWeight: 700, letterSpacing: '0.08em', color: '#0B0B0E', background: ACCENT, padding: '3px 8px', borderRadius: 7 }}>TODAY</span>}
                    </div>
                    {day.shows.length === 0 && <div style={{ padding: '13px 2px', fontSize: 13, color: 'rgba(245,245,247,0.26)' }}>Nothing airing</div>}
                    <div style={{ display: 'flex', flexDirection: 'column', gap: 9, marginTop: 11 }}>
                      {day.shows.map((c) => (
                        <div key={c.id} onClick={() => setDetailId(c.id)} style={{ display: 'flex', alignItems: 'center', gap: 14, padding: 11, borderRadius: 15, background: 'rgba(255,255,255,0.028)', border: '1px solid rgba(255,255,255,0.06)', cursor: 'pointer' }}>
                          <Thumb cover={c.cover} hasCover={c.hasCover} w={46} h={64} r={9} />
                          <div style={{ flex: 1, minWidth: 0 }}>
                            <div style={{ fontSize: 15, fontWeight: 600, letterSpacing: '-0.015em', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{c.title}</div>
                            <div style={{ fontSize: 12.5, color: 'rgba(245,245,247,0.46)', marginTop: 3, fontFamily: "'Geist Mono',monospace" }}>Ep {c.nextEp} · {c.airTime}</div>
                            {c.isBehind && (
                              <div style={{ display: 'inline-flex', alignItems: 'center', gap: 6, marginTop: 7, padding: '3px 9px 3px 7px', borderRadius: 7, background: 'rgba(240,162,78,0.13)', fontSize: 11.5, fontWeight: 600, color: ACCENT }}>
                                <span style={{ width: 5, height: 5, borderRadius: '50%', background: ACCENT }} />{c.behindLabel}
                              </div>
                            )}
                          </div>
                          <div style={{ textAlign: 'right', flex: 'none' }}>
                            <div style={{ fontSize: 10, fontWeight: 600, letterSpacing: '0.1em', color: 'rgba(245,245,247,0.28)' }}>IN</div>
                            <div style={{ fontFamily: "'Geist Mono',monospace", fontSize: 16, fontWeight: 500, color: c.countdownColor, marginTop: 2 }}>{c.countdown}</div>
                          </div>
                        </div>
                      ))}
                    </div>
                  </div>
                ))}
              </div>
              )}
            </div>
          )}

          {/* ========== LIBRARY ========== */}
          {screen === 'library' && (
            <div style={{ animation: 'at-fadein .4s ease' }}>
              <div style={{ position: 'sticky', top: 0, zIndex: 4, background: 'linear-gradient(180deg,#0B0B0E 72%,rgba(11,11,14,0.82))', backdropFilter: 'blur(12px)', padding: '30px 20px 12px' }}>
                <h1 style={{ margin: 0, fontSize: 27, fontWeight: 600, letterSpacing: '-0.03em' }}>Library</h1>
                <SearchBox value={libQuery} onChange={setLibQuery} placeholder="Search your library" />
                {!libraryEmpty && (
                  <div className="at-scroll" style={{ display: 'flex', gap: 7, marginTop: 11, overflowX: 'auto' }}>
                    {filterChips.map((chip) => {
                      const on = libFilter === chip.key
                      return (
                        <button key={chip.key} aria-pressed={on} onClick={() => setLibFilter(chip.key)} style={{ flex: 'none', padding: '7px 14px', border: `1px solid ${on ? ACCENT : 'rgba(255,255,255,0.08)'}`, borderRadius: 20, cursor: 'pointer', fontSize: 12.5, fontWeight: 500, whiteSpace: 'nowrap', color: on ? '#0B0B0E' : 'rgba(245,245,247,0.7)', background: on ? ACCENT : 'rgba(255,255,255,0.04)', transition: 'all .16s' }}>{chip.label}</button>
                      )
                    })}
                  </div>
                )}
              </div>
              <div style={{ padding: '6px 20px 28px' }}>
                {error && <RetryBanner onRetry={() => setRefreshTick((t) => t + 1)} />}
                {loading && shows.length === 0 && <Loader />}
                {!loading && libGroups.length === 0 &&
                  (libraryEmpty ? (
                    <EmptyState
                      title="Your library is empty"
                      body="Add anime from the Add tab and they’ll show up here, grouped by what’s behind, caught up, and finished."
                      ctaLabel="Add anime"
                      onCta={() => go('search')}
                    />
                  ) : libQuery.trim() ? (
                    <div style={{ padding: '60px 20px', textAlign: 'center', color: 'rgba(245,245,247,0.4)', fontSize: 14 }}>No shows match “{libQuery.trim()}”.</div>
                  ) : (
                    <div style={{ padding: '60px 20px', textAlign: 'center', color: 'rgba(245,245,247,0.4)', fontSize: 14 }}>Nothing in this filter yet.</div>
                  ))}
                {libGroups.map((g) => (
                  <div key={g.label} style={{ marginTop: 22 }}>
                    <div style={{ display: 'flex', alignItems: 'baseline', gap: 8, marginBottom: 13 }}>
                      <h2 style={{ margin: 0, fontSize: 12.5, fontWeight: 600, letterSpacing: '0.06em', textTransform: 'uppercase', color: 'rgba(245,245,247,0.7)' }}>{g.label}</h2>
                      <span style={{ fontSize: 12, color: 'rgba(245,245,247,0.36)', fontFamily: "'Geist Mono',monospace" }}>{g.count}</span>
                    </div>
                    <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 13 }}>
                      {g.cards.map((vm) => (
                        <ShowCard key={vm.id} vm={vm} onOpen={() => setDetailId(vm.id)} onPrimary={(e) => { e.stopPropagation(); markCaughtUp(vm.id) }} />
                      ))}
                    </div>
                  </div>
                ))}
              </div>
            </div>
          )}

          {/* ========== ADD / SEARCH ========== */}
          {screen === 'search' && (
            <div style={{ animation: 'at-fadein .4s ease' }}>
              <div style={{ position: 'sticky', top: 0, zIndex: 4, background: 'linear-gradient(180deg,#0B0B0E 72%,rgba(11,11,14,0.82))', backdropFilter: 'blur(12px)', padding: '30px 20px 14px' }}>
                <h1 style={{ margin: 0, fontSize: 27, fontWeight: 600, letterSpacing: '-0.03em' }}>Add anime</h1>
                <SearchBox value={searchQuery} onChange={setSearchQuery} placeholder="Search AniList" />
              </div>
              <div style={{ padding: '8px 20px 28px' }}>
                <div style={{ fontSize: 12, color: searchError ? ACCENT : 'rgba(245,245,247,0.4)', marginBottom: 13 }}>{searchHint}</div>
                <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 13 }}>
                  {searchShows.map((s) => (
                    <ShowCard key={s.id} vm={cardVM(s, 'add', justCaught, now, lib.has(s.id))} onOpen={() => setDetailId(s.id)} onPrimary={(e) => { e.stopPropagation(); addToLibrary(s.id) }} />
                  ))}
                </div>
              </div>
            </div>
          )}
        </div>

        {/* ===== TAB BAR ===== */}
        <nav aria-label="Primary" style={{ flex: 'none', display: 'flex', padding: '9px 12px calc(14px + env(safe-area-inset-bottom))', borderTop: '1px solid rgba(255,255,255,0.06)', background: 'rgba(11,11,14,0.92)', backdropFilter: 'blur(14px)' }}>
          <TabButton label="Today" active={screen === 'home'} color={navColor('home')} onClick={() => go('home')} icon={<HomeIcon color={navColor('home')} />} />
          <TabButton label="Schedule" active={screen === 'schedule'} color={navColor('schedule')} onClick={() => go('schedule')} icon={<CalIcon color={navColor('schedule')} />} />
          <TabButton label="Library" active={screen === 'library'} color={navColor('library')} onClick={() => go('library')} icon={<LibIcon color={navColor('library')} />} />
          <TabButton label="Add" active={screen === 'search'} color={navColor('search')} onClick={() => go('search')} icon={<SearchIcon color={navColor('search')} />} />
        </nav>

        {/* ===== UNDO TOAST (above the detail sheet so in-sheet actions stay undoable) ===== */}
        {undo && (
          <div role="status" style={{ position: 'absolute', left: 16, right: 16, bottom: 'calc(84px + env(safe-area-inset-bottom))', zIndex: 50, margin: '0 auto', maxWidth: 360, display: 'flex', alignItems: 'center', gap: 12, padding: '11px 12px 11px 15px', borderRadius: 14, background: 'rgba(28,28,34,0.97)', backdropFilter: 'blur(16px)', border: '1px solid rgba(255,255,255,0.1)', boxShadow: '0 12px 40px rgba(0,0,0,0.55)', animation: 'at-toastin .3s cubic-bezier(.2,.9,.3,1)' }}>
            <div style={{ width: 20, height: 20, borderRadius: '50%', background: ACCENT, display: 'flex', alignItems: 'center', justifyContent: 'center', flex: 'none' }}><Check size={12} w={3.4} /></div>
            <span style={{ flex: 1, minWidth: 0, fontSize: 13.5, color: 'rgba(245,245,247,0.9)', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{undo.added ? `Added ${undo.title} to ${undo.statusLabel ?? 'library'}` : `Marked ${undo.title} · Ep ${undo.ep}`}</span>
            <button onClick={doUndo} style={{ flex: 'none', border: 'none', background: 'transparent', cursor: 'pointer', fontSize: 13.5, fontWeight: 600, color: ACCENT, padding: '4px 6px', borderRadius: 8 }}>Undo</button>
          </div>
        )}

        {/* ===== DETAIL SHEET ===== */}
        {detailShow && (
          <DetailSheet
            show={detailShow}
            inLibrary={detailInLib}
            now={now}
            justCaughtUp={justCaught.includes(detailShow.id)}
            onClose={closeDetail}
            onSetProgress={(v) => lib.setProgress(detailShow.id, v)}
            onCatchUp={() => markCaughtUp(detailShow.id)}
            onSetStatus={(st) => lib.setStatus(detailShow.id, st)}
            onAdd={() => addToLibrary(detailShow.id)}
          />
        )}
      </div>
    </div>
  )
}

// ---------- Detail sheet ----------
function DetailSheet({
  show,
  inLibrary,
  now,
  justCaughtUp,
  onClose,
  onSetProgress,
  onCatchUp,
  onSetStatus,
  onAdd,
}: {
  show: Show
  inLibrary: boolean
  now: number
  justCaughtUp: boolean
  onClose: () => void
  onSetProgress: (v: number) => void
  onCatchUp: () => void
  onSetStatus: (s: WatchStatus) => void
  onAdd: () => void
}) {
  const total = show.totalEpisodes
  const bh = episodesBehind(show)
  const statusMap: Record<WatchStatus, string> = { watching: 'Watching', completed: 'Completed', planned: 'Plan to watch' }
  const progressPct = (total ? Math.min(100, Math.round((100 * show.progress) / total)) : 0) + '%'
  const statusBtns: { key: WatchStatus; label: string }[] = [
    { key: 'watching', label: 'Watching' },
    { key: 'completed', label: 'Completed' },
    { key: 'planned', label: 'Plan' },
  ]
  // Upper bound for progress: latest aired for airing shows, full run for finished, else uncapped.
  const cap = show.isReleasing
    ? Math.max(show.airedEpisodes, show.progress)
    : total > 0
      ? total
      : Number.POSITIVE_INFINITY
  const canInc = show.progress < cap
  const canDec = show.progress > 0

  // Move keyboard focus into the sheet on open so Esc/tab work and focus isn't stranded behind it.
  const sheetRef = useRef<HTMLDivElement>(null)
  useEffect(() => {
    sheetRef.current?.focus()
  }, [])

  return (
    <div ref={sheetRef} role="dialog" aria-modal="true" aria-label={show.title} tabIndex={-1} style={{ position: 'absolute', inset: 0, zIndex: 40, background: '#0B0B0E', display: 'flex', flexDirection: 'column', outline: 'none', animation: 'at-sheetin .34s cubic-bezier(.2,.9,.3,1)' }}>
      <div className="at-scroll" style={{ flex: 1, overflowY: 'auto' }}>
        <div style={{ position: 'relative', height: 236, overflow: 'hidden' }}>
          <BannerImg src={show.banner} opacity={0.6} />
          <div style={{ position: 'absolute', inset: 0, background: 'linear-gradient(0deg,#0B0B0E 3%,rgba(11,11,14,0.35) 52%,rgba(11,11,14,0.5))' }} />
          <button onClick={onClose} aria-label="Close" style={{ position: 'absolute', top: 'calc(18px + env(safe-area-inset-top))', left: 16, width: 40, height: 40, border: 'none', borderRadius: '50%', cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', background: 'rgba(11,11,14,0.55)', backdropFilter: 'blur(10px)', boxShadow: '0 0 0 1px rgba(255,255,255,0.1)' }}>
            <svg width={20} height={20} viewBox="0 0 24 24" fill="none" stroke="#F5F5F7" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round"><path d="M15 6 9 12l6 6" /></svg>
          </button>
        </div>
        <div style={{ padding: '0 20px 40px', marginTop: -80, position: 'relative' }}>
          <div style={{ display: 'flex', gap: 16, alignItems: 'flex-end' }}>
            <div style={{ flex: 'none', borderRadius: 13, boxShadow: '0 16px 40px rgba(0,0,0,0.6)' }}>
              <Thumb cover={show.cover} hasCover={!!show.cover} w={108} h={160} r={13} />
            </div>
            <div style={{ flex: 1, minWidth: 0, paddingBottom: 6 }}>
              {bh > 0 && <div style={{ display: 'inline-block', padding: '4px 10px', borderRadius: 8, background: ACCENT, fontSize: 11.5, fontWeight: 600, color: '#0B0B0E', marginBottom: 9 }}>{bh} behind</div>}
              <div style={{ fontSize: 13, color: 'rgba(245,245,247,0.5)', fontFamily: "'Geist Mono',monospace" }}>{inLibrary ? statusMap[show.status] : 'Not in library'}</div>
            </div>
          </div>
          <h1 style={{ margin: '18px 0 0', fontSize: 24, fontWeight: 600, letterSpacing: '-0.03em', lineHeight: 1.12 }}>{show.title}</h1>
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 7, marginTop: 13 }}>
            {show.genres.map((g) => (
              <span key={g} style={{ padding: '5px 11px', borderRadius: 8, background: 'rgba(255,255,255,0.05)', border: '1px solid rgba(255,255,255,0.06)', fontSize: 12, color: 'rgba(245,245,247,0.62)' }}>{g}</span>
            ))}
          </div>

          {show.isReleasing && show.nextAiringAt && (
            <div style={{ display: 'flex', alignItems: 'center', gap: 13, marginTop: 20, padding: '14px 16px', borderRadius: 15, background: 'rgba(240,162,78,0.08)', border: '1px solid rgba(240,162,78,0.18)' }}>
              <ClockIcon color={ACCENT} size={20} />
              <div style={{ flex: 1 }}>
                <div style={{ fontSize: 13, color: 'rgba(245,245,247,0.6)' }}>Episode {show.nextEpisodeNumber} airs {fmtDay(show.nextAiringAt, now)}</div>
                <div style={{ fontSize: 12, color: 'rgba(245,245,247,0.4)', marginTop: 1, fontFamily: "'Geist Mono',monospace" }}>{fmtTime(show.nextAiringAt)}</div>
              </div>
              <div style={{ fontFamily: "'Geist Mono',monospace", fontSize: 18, fontWeight: 500, color: ACCENT }}>{fmtCountdown(show.nextAiringAt, now)}</div>
            </div>
          )}

          <p style={{ margin: '20px 0 0', fontSize: 14.5, lineHeight: 1.6, color: 'rgba(245,245,247,0.66)' }}>{show.synopsis || 'No synopsis available.'}</p>

          {inLibrary ? (
            <>
              <div style={{ marginTop: 24, padding: 18, borderRadius: 16, background: 'rgba(255,255,255,0.03)', border: '1px solid rgba(255,255,255,0.06)' }}>
                <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between' }}>
                  <span style={{ fontSize: 13, fontWeight: 500, color: 'rgba(245,245,247,0.7)' }}>Episodes watched</span>
                  <span style={{ fontFamily: "'Geist Mono',monospace", fontSize: 14, color: 'rgba(245,245,247,0.5)' }}>{show.progress} / {total || '?'}</span>
                </div>
                <div style={{ height: 5, borderRadius: 5, background: 'rgba(255,255,255,0.12)', overflow: 'hidden', marginTop: 11 }}>
                  <div style={{ height: '100%', borderRadius: 5, background: ACCENT, width: progressPct, transition: 'width .3s' }} />
                </div>
                <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginTop: 16 }}>
                  <button onClick={() => canDec && onSetProgress(show.progress - 1)} disabled={!canDec} aria-label="One fewer episode" style={{ width: 44, height: 44, border: '1px solid rgba(255,255,255,0.12)', borderRadius: 12, background: 'rgba(255,255,255,0.04)', cursor: canDec ? 'pointer' : 'default', opacity: canDec ? 1 : 0.35, color: '#F5F5F7', fontSize: 22, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>−</button>
                  <div style={{ flex: 1, textAlign: 'center', fontFamily: "'Geist Mono',monospace", fontSize: 22, fontWeight: 500 }}>{show.progress}</div>
                  <button onClick={() => canInc && onSetProgress(show.progress + 1)} disabled={!canInc} aria-label="One more episode" style={{ width: 44, height: 44, border: '1px solid rgba(255,255,255,0.12)', borderRadius: 12, background: 'rgba(255,255,255,0.04)', cursor: canInc ? 'pointer' : 'default', opacity: canInc ? 1 : 0.35, color: '#F5F5F7', fontSize: 22, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>+</button>
                </div>
                {show.isReleasing && show.progress >= cap && cap > 0 && (
                  <div style={{ marginTop: 10, fontSize: 11.5, color: 'rgba(245,245,247,0.4)', textAlign: 'center' }}>Caught up to the latest aired episode.</div>
                )}
              </div>

              {show.isReleasing && bh > 0 && (
                <button onClick={onCatchUp} className="at-btn-primary" style={{ width: '100%', marginTop: 14, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 9, padding: 15, border: 'none', borderRadius: 15, cursor: 'pointer', fontSize: 15.5, fontWeight: 600, color: '#0B0B0E', background: ACCENT, boxShadow: '0 6px 26px rgba(240,162,78,0.32)' }}>
                  <Check size={19} />Mark caught up · Ep {show.airedEpisodes}
                </button>
              )}

              <div style={{ marginTop: 22 }}>
                <div style={{ fontSize: 12, fontWeight: 600, letterSpacing: '0.05em', textTransform: 'uppercase', color: 'rgba(245,245,247,0.4)', marginBottom: 10 }}>Status</div>
                <div style={{ display: 'flex', gap: 8 }}>
                  {statusBtns.map((b) => {
                    const on = show.status === b.key
                    return (
                      <button key={b.key} aria-pressed={on} onClick={() => onSetStatus(b.key)} style={{ flex: 1, padding: '11px 0', border: `1px solid ${on ? ACCENT : 'rgba(255,255,255,0.08)'}`, borderRadius: 12, cursor: 'pointer', fontSize: 12.5, fontWeight: 500, color: on ? '#0B0B0E' : 'rgba(245,245,247,0.7)', background: on ? ACCENT : 'rgba(255,255,255,0.04)', transition: 'all .16s' }}>{b.label}</button>
                    )
                  })}
                </div>
              </div>
            </>
          ) : (
            <button onClick={onAdd} className="at-btn-primary" style={{ width: '100%', marginTop: 24, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 9, padding: 15, border: 'none', borderRadius: 15, cursor: 'pointer', fontSize: 15.5, fontWeight: 600, color: '#0B0B0E', background: ACCENT, boxShadow: '0 6px 26px rgba(240,162,78,0.32)' }}>
              <Plus size={19} w={2.6} />
              Add to library
            </button>
          )}
        </div>
      </div>
      {justCaughtUp && <CaughtUpOverlay size={62} />}
    </div>
  )
}

// ---------- Small building blocks ----------
function BriefingRow({ vm, onOpen, onPrimary }: { vm: CardVM; onOpen: () => void; onPrimary: () => void }) {
  return (
    <div style={{ position: 'relative', padding: 13, borderRadius: 18, background: 'rgba(255,255,255,0.028)', border: '1px solid rgba(255,255,255,0.07)', overflow: 'hidden', animation: 'at-fadeup .42s ease both' }}>
      <div style={{ display: 'flex', gap: 14, alignItems: 'center' }}>
        <div onClick={onOpen} style={{ cursor: 'pointer' }}>
          <Thumb cover={vm.cover} hasCover={vm.hasCover} w={54} h={80} r={10} />
        </div>
        <div onClick={onOpen} style={{ flex: 1, minWidth: 0, cursor: 'pointer' }}>
          <div style={{ fontSize: 16, fontWeight: 600, letterSpacing: '-0.02em', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{vm.title}</div>
          <div style={{ marginTop: 5, fontSize: 13, color: ACCENT, fontWeight: 500 }}>Ep {vm.airedEpisodes} just aired</div>
          <div style={{ marginTop: 2, fontSize: 12, color: 'rgba(245,245,247,0.42)', fontFamily: "'Geist Mono',monospace" }}>{vm.airedAgo}{vm.behindLabel ? ` · ${vm.behindLabel}` : ''}</div>
        </div>
      </div>
      <button onClick={onPrimary} className="at-btn-primary" style={{ width: '100%', marginTop: 12, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8, padding: 12, border: 'none', borderRadius: 13, cursor: 'pointer', fontSize: 14.5, fontWeight: 600, color: '#0B0B0E', background: ACCENT, boxShadow: '0 4px 18px rgba(240,162,78,0.26)' }}>
        <Check size={17} />Mark caught up
      </button>
      {vm.justCaughtUp && <CaughtUpOverlay size={50} />}
    </div>
  )
}

function HeroCard({ vm, onOpen, onPrimary }: { vm: CardVM; onOpen: () => void; onPrimary: () => void }) {
  return (
    <div style={{ position: 'relative', borderRadius: 20, overflow: 'hidden', background: '#16161B', border: '1px solid rgba(255,255,255,0.07)', animation: 'at-fadeup .42s ease both' }}>
      <div style={{ position: 'relative', height: 168, overflow: 'hidden' }}>
        <BannerImg src={vm.banner} opacity={0.55} />
        <div style={{ position: 'absolute', inset: 0, background: 'linear-gradient(0deg,#16161B 6%,rgba(22,22,27,0.2) 60%,transparent)' }} />
        <div style={{ position: 'absolute', top: 13, left: 13, padding: '4px 10px', borderRadius: 8, background: 'rgba(240,162,78,0.92)', fontSize: 11, fontWeight: 600, color: '#0B0B0E', letterSpacing: '0.04em' }}>FRESH EPISODE</div>
      </div>
      <div style={{ display: 'flex', gap: 15, padding: '0 16px 16px', marginTop: -44, position: 'relative' }}>
        <div onClick={onOpen} style={{ width: 84, height: 124, flex: 'none', borderRadius: 12, overflow: 'hidden', boxShadow: '0 12px 30px rgba(0,0,0,0.55)', cursor: 'pointer', background: '#16161B' }}>
          <Thumb cover={vm.cover} hasCover={vm.hasCover} w={84} h={124} r={0} />
        </div>
        <div style={{ flex: 1, minWidth: 0, paddingTop: 50 }}>
          <div onClick={onOpen} style={{ fontSize: 19, fontWeight: 600, letterSpacing: '-0.025em', lineHeight: 1.15, cursor: 'pointer', overflow: 'hidden', display: '-webkit-box', WebkitLineClamp: 2, WebkitBoxOrient: 'vertical' }}>{vm.title}</div>
          <div style={{ marginTop: 6, fontSize: 13, color: 'rgba(245,245,247,0.62)' }}><span style={{ color: ACCENT, fontWeight: 500 }}>Ep {vm.airedEpisodes}</span> · {vm.airedAgo}</div>
        </div>
      </div>
      <div style={{ padding: '0 16px 16px' }}>
        <button onClick={onPrimary} className="at-btn-primary" style={{ width: '100%', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8, padding: 13, border: 'none', borderRadius: 13, cursor: 'pointer', fontSize: 15, fontWeight: 600, color: '#0B0B0E', background: ACCENT, boxShadow: '0 4px 20px rgba(240,162,78,0.28)' }}>
          <Check size={18} />Mark caught up
        </button>
      </div>
      {vm.justCaughtUp && <CaughtUpOverlay size={62} />}
    </div>
  )
}

function Thumb({ cover, hasCover, w, h, r }: { cover: string; hasCover: boolean; w: number; h: number; r: number }) {
  return (
    <div style={{ width: w, height: h, flex: 'none', borderRadius: r, overflow: 'hidden', background: '#16161B' }}>
      {hasCover ? (
        <div style={{ width: '100%', height: '100%', backgroundImage: `url(${cover})`, backgroundSize: 'cover', backgroundPosition: 'center' }} />
      ) : (
        <div style={{ width: '100%', height: '100%', background: 'linear-gradient(150deg,#27272f,#141418)' }} />
      )}
    </div>
  )
}

function SearchBox({ value, onChange, placeholder }: { value: string; onChange: (v: string) => void; placeholder: string }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginTop: 14, padding: '11px 14px', borderRadius: 13, background: 'rgba(255,255,255,0.04)', border: '1px solid rgba(255,255,255,0.07)' }}>
      <svg width={17} height={17} viewBox="0 0 24 24" fill="none" stroke="rgba(245,245,247,0.4)" strokeWidth={1.9} strokeLinecap="round" strokeLinejoin="round"><circle cx="11" cy="11" r="7" /><path d="m20 20-3.6-3.6" /></svg>
      <input value={value} onChange={(e) => onChange(e.target.value)} placeholder={placeholder} style={{ flex: 1, border: 'none', background: 'transparent', outline: 'none', color: '#F5F5F7', fontSize: 15, letterSpacing: '-0.01em' }} />
    </div>
  )
}

function Loader() {
  return (
    <div style={{ display: 'flex', justifyContent: 'center', padding: '60px 0' }}>
      <div style={{ width: 28, height: 28, borderRadius: '50%', border: '2.5px solid rgba(255,255,255,0.12)', borderTopColor: ACCENT, animation: 'at-spin .8s linear infinite' }} />
    </div>
  )
}

// Friendly empty / first-run state with an optional call-to-action.
function EmptyState({ title, body, ctaLabel, onCta }: { title: string; body: string; ctaLabel?: string; onCta?: () => void }) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', textAlign: 'center', padding: '70px 20px 40px', animation: 'at-fadeup .5s ease' }}>
      <div style={{ fontSize: 30, color: ACCENT, textShadow: '0 0 30px rgba(240,162,78,0.55)' }}>✦</div>
      <div style={{ marginTop: 16, fontSize: 21, fontWeight: 600, letterSpacing: '-0.02em' }}>{title}</div>
      <div style={{ marginTop: 9, fontSize: 14, color: 'rgba(245,245,247,0.5)', maxWidth: 290, lineHeight: 1.5 }}>{body}</div>
      {ctaLabel && onCta && (
        <button onClick={onCta} className="at-btn-primary" style={{ marginTop: 22, display: 'inline-flex', alignItems: 'center', gap: 8, padding: '12px 22px', border: 'none', borderRadius: 13, cursor: 'pointer', fontSize: 14.5, fontWeight: 600, color: '#0B0B0E', background: ACCENT, boxShadow: '0 6px 26px rgba(240,162,78,0.32)' }}>
          <Plus size={17} w={2.6} />
          {ctaLabel}
        </button>
      )}
    </div>
  )
}

// Inline, dismissible-style banner when live data couldn't be reached (data may be stale/missing).
function RetryBanner({ onRetry }: { onRetry: () => void }) {
  return (
    <div role="alert" style={{ display: 'flex', alignItems: 'center', gap: 12, marginTop: 16, padding: '12px 14px', borderRadius: 13, background: 'rgba(240,162,78,0.08)', border: '1px solid rgba(240,162,78,0.2)' }}>
      <div style={{ flex: 1, fontSize: 13, color: 'rgba(245,245,247,0.72)', lineHeight: 1.4 }}>Couldn’t reach AniList. Showing what’s saved.</div>
      <button onClick={onRetry} style={{ flex: 'none', border: 'none', background: ACCENT, color: '#0B0B0E', fontWeight: 600, fontSize: 13, padding: '7px 14px', borderRadius: 9, cursor: 'pointer' }}>Retry</button>
    </div>
  )
}

function TabButton({ label, color, active, onClick, icon }: { label: string; color: string; active: boolean; onClick: () => void; icon: ReactNode }) {
  return (
    <button onClick={onClick} aria-label={label} aria-current={active ? 'page' : undefined} style={{ flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 5, border: 'none', background: 'transparent', cursor: 'pointer', padding: '6px 0' }}>
      {icon}
      <span style={{ fontSize: 10.5, fontWeight: 500, color }}>{label}</span>
    </button>
  )
}

// ---------- Tab + misc icons ----------
const HomeIcon = ({ color }: { color: string }) => (
  <svg width={22} height={22} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth={1.8} strokeLinecap="round" strokeLinejoin="round"><circle cx="12" cy="12" r="4.2" /><path d="M12 2.6v2.3M12 19.1v2.3M21.4 12h-2.3M4.9 12H2.6M18.4 5.6l-1.6 1.6M7.2 16.8l-1.6 1.6M18.4 18.4l-1.6-1.6M7.2 7.2 5.6 5.6" /></svg>
)
const CalIcon = ({ color }: { color: string }) => (
  <svg width={22} height={22} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth={1.8} strokeLinecap="round" strokeLinejoin="round"><rect x="3.4" y="4.6" width="17.2" height="15.8" rx="2.6" /><path d="M3.4 9h17.2M8 2.7v3.4M16 2.7v3.4" /></svg>
)
const LibIcon = ({ color }: { color: string }) => (
  <svg width={22} height={22} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth={1.8} strokeLinecap="round" strokeLinejoin="round"><rect x="3.6" y="3.6" width="6.8" height="16.8" rx="1.8" /><rect x="13.6" y="3.6" width="6.8" height="16.8" rx="1.8" /></svg>
)
const SearchIcon = ({ color }: { color: string }) => (
  <svg width={22} height={22} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth={1.8} strokeLinecap="round" strokeLinejoin="round"><circle cx="11" cy="11" r="6.6" /><path d="m20 20-3.4-3.4" /></svg>
)
const ClockIcon = ({ color = 'rgba(245,245,247,0.5)', size = 14 }: { color?: string; size?: number }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth={1.9} strokeLinecap="round" strokeLinejoin="round"><circle cx="12" cy="12" r="9" /><path d="M12 7v5l3 2" /></svg>
)
