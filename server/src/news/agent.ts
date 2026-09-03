import os from 'node:os'
import { query } from '@anthropic-ai/claude-agent-sdk'
import { z } from 'zod'
import { env } from '../env.js'
import type { FranchiseUpcoming, MediaSource } from '../types/api.js'

export const UPCOMING_STATUSES = [
  'airing',
  'upcoming_dated',
  'announced',
  'announced_no_date',
  'recently_aired',
  'rumored',
  'concluded',
] as const

const newsResultSchema = z.object({
  status: z.enum(UPCOMING_STATUSES),
  next: z.string(),
  release: z.string(),
  note: z.string().nullable(),
  source: z.string().nullable(),
  evidence: z.array(z.object({
    url: z.string().url(),
    publisher: z.string().nullable(),
    publishedAt: z.string().nullable(),
    tier: z.enum(['official', 'trade', 'reputable', 'catalogue', 'unknown']),
    primary: z.boolean(),
  })).max(5),
})

export type NewsResult = z.infer<typeof newsResultSchema>

// Raw JSON Schema for the SDK's structured-output enforcement (kept explicit rather than
// derived so the wire contract is visible at a glance).
const NEWS_JSON_SCHEMA = {
  type: 'object',
  properties: {
    status: { type: 'string', enum: [...UPCOMING_STATUSES] },
    next: { type: 'string' },
    release: { type: 'string' },
    note: { type: ['string', 'null'] },
    source: { type: ['string', 'null'] },
    evidence: {
      type: 'array',
      maxItems: 5,
      items: {
        type: 'object',
        properties: {
          url: { type: 'string' },
          publisher: { type: ['string', 'null'] },
          publishedAt: { type: ['string', 'null'] },
          tier: { type: 'string', enum: ['official', 'trade', 'reputable', 'catalogue', 'unknown'] },
          primary: { type: 'boolean' },
        },
        required: ['url', 'publisher', 'publishedAt', 'tier', 'primary'],
        additionalProperties: false,
      },
    },
  },
  required: ['status', 'next', 'release', 'note', 'source', 'evidence'],
  additionalProperties: false,
} as const

export interface NewsResearchInput {
  title: string
  /** Selects source-appropriate language and authorities for anime versus general television. */
  catalogueSource: MediaSource
  /** Short descriptions of the parts we already track, e.g. "Season 2 (TV, FINISHED, 2024)". */
  knownParts: string[]
  /** What we currently believe (last run's result), if anything. */
  current: FranchiseUpcoming | null
  /** Upcoming installments already recorded, e.g. "Season 4 (announced_no_date)". */
  knownAnnouncements: string[]
}

export function buildNewsPrompt(input: NewsResearchInput): string {
  const parts = input.knownParts.length
    ? input.knownParts.map((p) => `- ${p}`).join('\n')
    : '- (none tracked yet)'
  const current = input.current
    ? `Our current belief (from a previous check on ${input.current.checked ?? 'unknown date'}): status=${input.current.status}, next="${input.current.next}", release="${input.current.release}". Verify whether this is still accurate or has progressed.`
    : 'We have no prior information about upcoming installments.'
  const known = input.knownAnnouncements.length
    ? `\nUpcoming installments we already recorded:\n${input.knownAnnouncements.map((a) => `- ${a}`).join('\n')}\nIf your finding refers to one of these, reuse EXACTLY the same name in \`next\` — do not reword it.`
    : ''

  const subject = input.catalogueSource === 'tmdb' ? 'television series' : 'anime franchise'
  const task =
    input.catalogueSource === 'tmdb'
      ? 'Search the web for the latest news about the NEXT installment of this series (new season, continuation, reunion/special, or direct follow-up). Cover official announcements with dates, official renewals without dates, and credible production reports or rumors. Prefer the official streamer/network or production company, then reputable trade publications such as Deadline, Variety, and The Hollywood Reporter. For Netflix titles, prefer Netflix Tudum or About Netflix. Ignore fan speculation and unsourced renewal predictions.'
      : 'Search the web for the latest news about the NEXT installment of this franchise (new season, sequel film, next part/cour, or direct continuation). Cover official announcements with dates, official announcements without dates, and credible production reports or rumors. Prefer the official site or official X/Twitter account, Anime News Network, Crunchyroll News, Natalie, or Oricon. Ignore fan speculation with no sourcing.'

  return `You are researching official news about the ${subject} "${input.title}".

Installments we already track:
${parts}

${current}${known}

Today's date: ${new Date().toISOString().slice(0, 10)}.

Task: ${task}

Important: "next" means the earliest installment the viewer has not received yet, not an
installment after every row in our catalogue. If Installments we already track contains a
RELEASING or NOT_YET_RELEASED season/film, report and verify that installment first. Do not call a
series concluded merely because that already-catalogued future installment is its announced final
season.

Classify the situation into exactly one status:
- airing: the next installment is currently airing
- upcoming_dated: officially announced with a specific premiere date (day-level)
- announced: officially announced with a coarse release window (a season/quarter/year, e.g. "Fall 2026")
- announced_no_date: officially announced ("in production") with no date or window at all
- rumored: only credible rumors or unconfirmed reports exist
- recently_aired: the latest installment finished within roughly the last 3 months and nothing new is announced
- concluded: the story is finished / studio confirmed no continuation / nothing found at all

Field conventions:
- next: the SHORTEST stable name for the installment. For a numbered TV season use exactly "Season N" (no subtitle), "<subtitle> (movie)" for films, "Final Season Part N" style only when that is the official naming. Empty string when status is recently_aired or concluded.
- release: a human-readable date or window ("2027-01-09", "January 2027", "Fall 2026"). "TBA" when unknown.
- note: one short sentence of context (what was announced, by whom, when) or null.
- source: the URL of the single most authoritative source you found, or null.
- evidence: up to 5 sources that directly support the classification. Prefer an official primary
  announcement plus an independent reputable/trade report when both exist. Set tier=official for
  the studio/network/streamer/production account, trade for industry publications, reputable for
  established news outlets, catalogue only for AniList/TMDB, and unknown otherwise. Set primary
  true only for the original announcement. Never include search-result pages or fan speculation.`
}

// The agent subprocess resolves credentials like Claude Code: an ANTHROPIC_API_KEY in its
// environment takes precedence over the machine's Claude Code (subscription) login. The
// server's .env carries an API key, so strip it here — news research rides the subscription,
// not metered API billing.
function subprocessEnv(): Record<string, string> {
  const out: Record<string, string> = {}
  for (const [k, v] of Object.entries(process.env)) {
    if (v != null && k !== 'ANTHROPIC_API_KEY') out[k] = v
  }
  return out
}

/**
 * Run one web-research pass for a franchise using the Claude Agent SDK (web tools only,
 * no filesystem/shell access). Returns null when the agent fails, times out, or produces
 * output that doesn't validate — callers should treat that as "no new information".
 */
export async function researchFranchiseNews(input: NewsResearchInput): Promise<NewsResult | null> {
  const q = query({
    prompt: buildNewsPrompt(input),
    options: {
      allowedTools: ['WebSearch', 'WebFetch'],
      permissionMode: 'dontAsk',
      outputFormat: { type: 'json_schema', schema: NEWS_JSON_SCHEMA },
      maxTurns: env.NEWS_AGENT_MAX_TURNS,
      ...(env.NEWS_AGENT_MODEL ? { model: env.NEWS_AGENT_MODEL } : {}),
      // Isolated from this repo: no CLAUDE.md / settings / skills, neutral cwd.
      settingSources: [],
      cwd: os.tmpdir(),
      env: subprocessEnv(),
    },
  })

  const timer = setTimeout(() => {
    void q.interrupt().catch(() => {})
  }, env.NEWS_AGENT_TIMEOUT_MS)

  try {
    for await (const message of q) {
      if (message.type !== 'result') continue
      if (message.subtype === 'success') {
        const raw = (message as { structured_output?: unknown }).structured_output
        const cost = (message as { total_cost_usd?: number }).total_cost_usd
        const parsed = newsResultSchema.safeParse(raw)
        if (!parsed.success) {
          console.warn(`[news] "${input.title}": structured output failed validation:`, parsed.error.message)
          return null
        }
        // total_cost_usd is the SDK's token-cost estimate — informational only when the
        // agent runs on subscription auth (no API key in the subprocess env).
        if (cost != null) console.log(`[news] "${input.title}": ${parsed.data.status} (~$${cost.toFixed(4)} tokens est.)`)
        return parsed.data
      }
      console.warn(`[news] "${input.title}": agent ended with ${message.subtype}`)
      return null
    }
    return null
  } catch (err) {
    console.warn(`[news] "${input.title}": agent error:`, (err as Error).message)
    return null
  } finally {
    clearTimeout(timer)
  }
}
