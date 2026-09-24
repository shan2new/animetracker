const TITLE_EDGE = new Set([' ', '-', '–', '—', ':'])

/**
 * The short form of a show's title that the apps print — "Re:ZERO" for "Re:ZERO -Starting Life in
 * Another World-", "TSUKIMICHI" for "TSUKIMICHI -Moonlit Fantasy-". A port of iOS
 * `String.shelfShortened` (DesignSystem/Primitives.swift), so a sentence the server writes
 * ("Because you finished Re:ZERO") names a show exactly as every row and shelf does.
 */
export function displayTitle(title: string): string {
  const original = title.trim()
  let s = original
  // A trailing "-…-" subtitle wrapper.
  if (s.endsWith('-')) {
    const open = s.indexOf(' -')
    if (open >= 0) s = s.slice(0, open)
  }
  let start = 0
  let end = s.length
  while (start < end && TITLE_EDGE.has(s[start]!)) start++
  while (end > start && TITLE_EDGE.has(s[end - 1]!)) end--
  s = s.slice(start, end)
  if (!s) return original
  // A long "Title: Subtitle" keeps its identity half rather than an ellipsis mid-word.
  if ([...s].length <= 40) return s
  for (const sep of [': ', ' – ', ' — ', ' - ', ' (']) {
    const at = s.indexOf(sep)
    if (at >= 0 && [...s.slice(0, at)].length >= 12) return s.slice(0, at)
  }
  return s
}

/** Strip HTML tags + collapse whitespace, truncating long synopses. Ported from format.ts. */
export function stripHtml(s: string | null | undefined): string {
  if (!s) return ''
  const text = s.replace(/<[^>]+>/g, '').replace(/\s+/g, ' ').trim()
  return text.length > 600 ? text.slice(0, 597).trim() + '…' : text
}
