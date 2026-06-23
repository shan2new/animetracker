import { env } from '../env.js'
import type { PartKind } from './partKind.js'

// What we feed the model about each candidate media in a component.
export interface GroupingCandidate {
  id: number
  title: string
  format: string | null
  status: string | null
  seasonYear: number | null
  episodes: number | null
  synopsis: string
}

export interface GroupingEdge {
  from: number
  to: number
  type: string
}

export interface GroupingInput {
  candidates: GroupingCandidate[]
  edges: GroupingEdge[]
}

export interface GroupedPart {
  id: number
  partKind: PartKind
  sequence: number
  label: string
}

export interface GroupedFranchise {
  canonicalName: string
  parts: GroupedPart[]
}

export interface GroupingResult {
  franchises: GroupedFranchise[]
  confidence: number
  model: string | null
}

export interface LlmGrouper {
  group(input: GroupingInput): Promise<GroupingResult>
}

const PART_KINDS: PartKind[] = ['season', 'movie', 'ova', 'ona', 'special', 'music']

export type GroupingTier = 'deterministic' | 'standard' | 'escalate'

/**
 * Decide how much model muscle a component deserves — the cost lever.
 *
 * The relation graph (graph.ts) only follows intra-franchise edges, so by construction almost
 * every component is a single franchise. The LLM's ONLY real value-add over deterministic
 * grouping is splitting a SIDE_STORY that's actually a separate work. A component with no
 * side-story (or a single member) has nothing to decide — deterministic yields the same grouping
 * for free, so we never spend a token on it. A component with two or more distinct side-story
 * targets is the genuinely ambiguous case worth the stronger (escalate) model; a single
 * side-story goes to the cheap standard model.
 */
export function groupingTier(input: GroupingInput): GroupingTier {
  if (input.candidates.length <= 1) return 'deterministic'
  const sideStoryTargets = new Set(input.edges.filter((e) => e.type === 'SIDE_STORY').map((e) => e.to))
  if (sideStoryTargets.size === 0) return 'deterministic'
  return sideStoryTargets.size >= 2 ? 'escalate' : 'standard'
}

// Strict JSON schema OpenRouter enforces on the response.
const RESPONSE_SCHEMA = {
  name: 'franchise_grouping',
  strict: true,
  schema: {
    type: 'object',
    additionalProperties: false,
    required: ['franchises'],
    properties: {
      franchises: {
        type: 'array',
        items: {
          type: 'object',
          additionalProperties: false,
          required: ['canonical_name', 'parts'],
          properties: {
            canonical_name: { type: 'string' },
            parts: {
              type: 'array',
              items: {
                type: 'object',
                additionalProperties: false,
                required: ['anilist_id', 'part_kind', 'sequence', 'label'],
                properties: {
                  anilist_id: { type: 'integer' },
                  part_kind: { type: 'string', enum: PART_KINDS },
                  sequence: { type: 'integer' },
                  label: { type: 'string' },
                },
              },
            },
          },
        },
      },
    },
  },
} as const

function buildPrompt(input: GroupingInput): string {
  const lines = input.candidates.map(
    (c) =>
      `- id=${c.id} | "${c.title}" | format=${c.format ?? '?'} | status=${c.status ?? '?'} | year=${
        c.seasonYear ?? '?'
      } | eps=${c.episodes ?? '?'}\n    synopsis: ${c.synopsis.slice(0, 280)}`,
  )
  const edges = input.edges.map((e) => `  ${e.from} --${e.type}--> ${e.to}`)
  return [
    'You are organizing anime metadata into canonical franchises.',
    'These AniList entries were collected by walking prequel/sequel/parent/side-story relations,',
    'so they are USUALLY one franchise — but occasionally a side-story is really a separate work',
    'that should be its own franchise. Decide the grouping using titles, air years, and synopses.',
    '',
    'For each franchise, assign every member a part_kind (season|movie|ova|ona|special|music),',
    'an integer sequence (chronological order WITHIN that kind, starting at 1), and a short human',
    'label (e.g. "Season 1", "The Movie: Mugen Train", "OVA 2"). Cover all ids exactly once.',
    '',
    'CANDIDATES:',
    ...lines,
    '',
    'RELATIONS:',
    ...(edges.length ? edges : ['  (none)']),
  ].join('\n')
}

/** OpenRouter-backed grouper using strict JSON schema output. */
export class OpenRouterGrouper implements LlmGrouper {
  constructor(
    private apiKey: string,
    private model: string,
  ) {}

  async group(input: GroupingInput): Promise<GroupingResult> {
    const res = await fetch('https://openrouter.ai/api/v1/chat/completions', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${this.apiKey}`,
        'Content-Type': 'application/json',
        'X-Title': 'AniTrack franchise grouper',
      },
      body: JSON.stringify({
        model: this.model,
        messages: [
          { role: 'system', content: 'Return only data conforming to the schema. Be precise and conservative about splitting.' },
          { role: 'user', content: buildPrompt(input) },
        ],
        response_format: { type: 'json_schema', json_schema: RESPONSE_SCHEMA },
        temperature: 0,
        // Hard ceiling against a runaway/looping response. Output is one small object per
        // candidate (~25 tokens); this leaves generous headroom and caps the worst case.
        max_tokens: Math.min(8192, 1024 + input.candidates.length * 96),
        // Only route to providers that actually honor the strict JSON schema, so a fallback
        // provider can't silently return loosely-shaped JSON.
        provider: { require_parameters: true },
      }),
    })
    if (!res.ok) throw new Error(`OpenRouter ${res.status}: ${await res.text().catch(() => '')}`)
    const json = (await res.json()) as { choices: { message: { content: string } }[] }
    const content = json.choices?.[0]?.message?.content ?? '{"franchises":[]}'
    const parsed = JSON.parse(content) as {
      franchises: { canonical_name: string; parts: { anilist_id: number; part_kind: PartKind; sequence: number; label: string }[] }[]
    }
    return {
      model: this.model,
      confidence: 0.9,
      franchises: parsed.franchises.map((f) => ({
        canonicalName: f.canonical_name,
        parts: f.parts.map((p) => ({ id: p.anilist_id, partKind: p.part_kind, sequence: p.sequence, label: p.label })),
      })),
    }
  }
}

/**
 * Deterministic grouper used when the LLM is disabled / no key: one franchise containing
 * everything, part_kind from format, sequence by air date within each kind.
 */
export class DeterministicGrouper implements LlmGrouper {
  async group(input: GroupingInput): Promise<GroupingResult> {
    const { deterministicGroup } = await import('./deterministic.js')
    return deterministicGroup(input)
  }
}

/** Pick the grouper based on env. */
export function makeGrouper(model = env.OPENROUTER_MODEL): LlmGrouper {
  if (env.GROUPING_LLM_DISABLED || !env.OPENROUTER_API_KEY) return new DeterministicGrouper()
  return new OpenRouterGrouper(env.OPENROUTER_API_KEY, model)
}
