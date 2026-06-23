/** Strip HTML tags + collapse whitespace, truncating long synopses. Ported from format.ts. */
export function stripHtml(s: string | null | undefined): string {
  if (!s) return ''
  const text = s.replace(/<[^>]+>/g, '').replace(/\s+/g, ' ').trim()
  return text.length > 600 ? text.slice(0, 597).trim() + '…' : text
}
