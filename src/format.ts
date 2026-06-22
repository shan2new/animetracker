// Time/date formatters (all in IST — Asia/Kolkata) plus the AniList → Show mapper.
import type { AniListMedia, LibraryEntry, Show } from './types'

/** Unwatched episodes that have already aired (0 unless the show is currently releasing). */
export function episodesBehind(s: Show): number {
  return s.isReleasing ? Math.max(0, s.airedEpisodes - s.progress) : 0
}

export const D = 86400e3
export const H = 3600e3
export const TZ = 'Asia/Kolkata'

const MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']
const MON_FULL = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December']
const WD_FULL = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday']
const WD_SHORT = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']

const WD_INDEX: Record<string, number> = { Sun: 0, Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6 }

const istFmt = new Intl.DateTimeFormat('en-US', {
  timeZone: TZ,
  year: 'numeric',
  month: 'numeric',
  day: 'numeric',
  hour: 'numeric',
  minute: '2-digit',
  weekday: 'short',
  hour12: false,
})

interface IstParts {
  y: number
  mo: number // 1-12
  d: number
  hour: number // 0-23
  minute: number
  wd: number // 0=Sun .. 6=Sat
}

/** Break a timestamp into its Indian Standard Time calendar/clock parts. */
export function istParts(ts: number): IstParts {
  const parts = istFmt.formatToParts(ts)
  const get = (t: string) => parts.find((p) => p.type === t)?.value ?? '0'
  let hour = parseInt(get('hour'), 10)
  if (hour === 24) hour = 0 // some engines emit 24 for midnight
  return {
    y: parseInt(get('year'), 10),
    mo: parseInt(get('month'), 10),
    d: parseInt(get('day'), 10),
    hour,
    minute: parseInt(get('minute'), 10),
    wd: WD_INDEX[get('weekday')] ?? 0,
  }
}

/** A UTC instant marking midnight of the IST calendar day containing ts — for day-diff / same-day math. */
export function istDayKey(ts: number): number {
  const p = istParts(ts)
  return Date.UTC(p.y, p.mo - 1, p.d)
}

/** Monday-first weekday index (0=Mon .. 6=Sun) in IST. */
export function istMondayCol(ts: number): number {
  return (istParts(ts).wd + 6) % 7
}

export function fmtCountdown(target: number, now: number): string {
  let s = Math.max(0, target - now)
  if (s < 6e4) return 'now'
  const d = Math.floor(s / D)
  s -= d * D
  const h = Math.floor(s / H)
  s -= h * H
  const m = Math.floor(s / 6e4)
  if (d > 0) return `${d}d ${h}h`
  if (h > 0) return `${h}h ${m}m`
  return `${m}m`
}

export function fmtTime(ts: number): string {
  const p = istParts(ts)
  const ap = p.hour >= 12 ? 'PM' : 'AM'
  const h = p.hour % 12 || 12
  return `${h}:${String(p.minute).padStart(2, '0')} ${ap} IST`
}

export function fmtAgo(ts: number, now: number): string {
  const s = Math.max(0, now - ts)
  const m = Math.floor(s / 6e4)
  if (m < 1) return 'just now'
  if (m < 60) return `${m}m ago`
  const h = Math.floor(m / 60)
  if (h < 24) return `${h}h ago`
  return `${Math.floor(h / 24)}d ago`
}

/** "Today" / "Tomorrow" / weekday — relative to the IST calendar. */
export function fmtDay(ts: number, now: number): string {
  const diff = Math.round((istDayKey(ts) - istDayKey(now)) / D)
  if (diff === 0) return 'Today'
  if (diff === 1) return 'Tomorrow'
  if (diff === -1) return 'Yesterday'
  return WD_SHORT[istParts(ts).wd]
}

export function fmtMonthDay(ts: number): string {
  const p = istParts(ts)
  return `${MON[p.mo - 1]} ${p.d}`
}

export function fmtTodayDate(now: number): string {
  const p = istParts(now)
  return `${WD_FULL[p.wd]}, ${MON_FULL[p.mo - 1]} ${p.d}`
}

export function greetingFor(now: number): string {
  const h = istParts(now).hour
  return h < 5 ? 'Late night' : h < 12 ? 'Good morning' : h < 18 ? 'Good afternoon' : 'Good evening'
}

export function weekdayNameMonFirst(col: number): string {
  // col 0=Mon .. 6=Sun
  return WD_FULL[(col + 1) % 7]
}

function stripHtml(s: string | null): string {
  if (!s) return ''
  const text = s.replace(/<[^>]+>/g, '').replace(/\s+/g, ' ').trim()
  return text.length > 440 ? text.slice(0, 437).trim() + '…' : text
}

/**
 * Merge a persisted library entry with its live AniList metadata into a UI Show.
 * `lastAiredAt` is the exact previous airing time (ms) from AniList's airingSchedules,
 * falling back to a weekly heuristic only while that data is still loading.
 */
export function toShow(entry: LibraryEntry, m: AniListMedia | undefined, lastAiredAt?: number): Show {
  const title = m?.title.english || m?.title.romaji || `Anime #${entry.id}`
  const isReleasing = m?.status === 'RELEASING'
  const total = m?.episodes ?? 0
  // Treat a non-positive airingAt as "no schedule" so bad data can't produce 1970 timestamps.
  const next = m?.nextAiringEpisode && m.nextAiringEpisode.airingAt > 0 ? m.nextAiringEpisode : null

  // Latest aired episode: one before the next airing. With no next episode, a finished show
  // has aired everything (total); a releasing show on hiatus has an unknown aired count, so we
  // fall back to the user's own progress — never inventing a "behind" or "caught up" we can't prove.
  const airedEpisodes = next ? Math.max(0, next.episode - 1) : isReleasing ? entry.progress : total
  const nextAiringAt = next ? next.airingAt * 1000 : null
  const resolvedLastAired =
    lastAiredAt != null && lastAiredAt > 0 ? lastAiredAt : next && next.episode > 1 ? next.airingAt * 1000 - 7 * D : null

  return {
    id: entry.id,
    status: entry.status,
    progress: entry.progress,
    title,
    cover: m?.coverImage.extraLarge || m?.coverImage.large || '',
    banner: m?.bannerImage || m?.coverImage.extraLarge || '',
    synopsis: stripHtml(m?.description ?? null),
    genres: (m?.genres ?? []).slice(0, 4),
    totalEpisodes: total,
    isReleasing,
    airedEpisodes,
    nextEpisodeNumber: next?.episode ?? null,
    nextAiringAt,
    lastAiredAt: resolvedLastAired,
  }
}
