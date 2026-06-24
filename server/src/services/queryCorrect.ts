import { env } from '../env.js'
import { cerebrasChat } from '../util/cerebras.js'

// Strict JSON schema the model must conform to: a single corrected string.
const RESPONSE_SCHEMA = {
  name: 'corrected_query',
  strict: true,
  schema: {
    type: 'object',
    additionalProperties: false,
    required: ['corrected'],
    properties: { corrected: { type: 'string' } },
  },
} as const

const SYSTEM_PROMPT = [
  'You normalize an anime search query to the canonical AniList title the user is reaching for.',
  'Do BOTH of these as needed:',
  '(1) Fix misspellings, spacing, and romanization slips toward the well-known romaji or English',
  'title (e.g. "Mushuko tensei" -> "Mushoku Tensei", "shingeki no kyogin" -> "Shingeki no Kyojin").',
  '(2) Complete an obvious partial title or prefix to the full well-known title (e.g. "Tsukimi" ->',
  '"Tsukimichi: Moonlit Fantasy", "kimetsu" -> "Kimetsu no Yaiba"). The user types as they go, so a',
  'truncated word usually means they want the show it begins.',
  'Only do this when the intended show is unambiguous. Never invent a show that does not exist, and',
  'do not add seasons/subtitles beyond the canonical base title. If the query is already a complete',
  'correct title, return it unchanged. Return only the resulting query string.',
].join(' ')

// Bound the extra latency a correction can add to a failed search. Cerebras typically answers in
// well under a second; if it stalls we abandon the correction rather than hang the request.
const TIMEOUT_MS = 4000

// Below this length a query is too short to complete/correct unambiguously (the user has barely
// started typing). Skip the LLM call rather than guess a title from one or two characters.
const MIN_CORRECT_LENGTH = 4

/**
 * Spell-correct AND prefix-complete a search query via Cerebras (AniList matches only whole word
 * tokens, so a typo'd or half-typed word returns nothing). Returns the normalized query, or null
 * when there is nothing useful to retry with: query too short, correction disabled, no API key, the
 * model errored/timed out, or the result is empty or unchanged from the input. Never throws — a
 * failed correction simply means the original (empty) search result stands.
 */
export async function correctSearchQuery(query: string): Promise<string | null> {
  const trimmed = query.trim()
  if (trimmed.length < MIN_CORRECT_LENGTH) return null
  if (env.SEARCH_CORRECT_DISABLED || !env.CEREBRAS_API_KEY) return null

  const controller = new AbortController()
  const timer = setTimeout(() => controller.abort(), TIMEOUT_MS)
  try {
    const res = await cerebrasChat(
      env.CEREBRAS_API_KEY,
      {
        model: env.CEREBRAS_MODEL,
        temperature: 0,
        max_tokens: 512,
        response_format: { type: 'json_schema', json_schema: RESPONSE_SCHEMA },
        messages: [
          { role: 'system', content: SYSTEM_PROMPT },
          { role: 'user', content: trimmed },
        ],
      },
      controller.signal,
    )
    if (!res.ok) return null
    const json = (await res.json()) as { choices?: { message?: { content?: string } }[] }
    const content = json.choices?.[0]?.message?.content
    if (!content) return null
    const corrected = (JSON.parse(content) as { corrected?: string }).corrected?.trim()
    if (!corrected) return null
    // Nothing to gain from re-searching the same string.
    if (corrected.toLowerCase() === trimmed.toLowerCase()) return null
    return corrected
  } catch {
    return null // disabled-by-failure: degrade to the original (empty) result
  } finally {
    clearTimeout(timer)
  }
}
