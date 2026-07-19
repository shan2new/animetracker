import 'dotenv/config'
import { z } from 'zod'

// Proper env-boolean: "1"/"true"/"yes"/"on" → true, everything else (incl. "0", "", "false") → false.
// NOTE: z.coerce.boolean() does Boolean(string), so "0" would wrongly become true — don't use it.
const envBool = (def: boolean) =>
  z
    .string()
    .optional()
    .transform((v) => (v == null ? def : ['1', 'true', 'yes', 'on'].includes(v.trim().toLowerCase())))

const schema = z.object({
  PORT: z.coerce.number().default(8787),
  CORS_ORIGIN: z.string().default('*'),
  DATABASE_URL: z.string().default('postgres://localhost:5432/anitrack'),

  CLERK_JWT_KEY: z.string().optional(),
  CLERK_SECRET_KEY: z.string().optional(),
  DEV_AUTH_BYPASS: envBool(false),

  OPENROUTER_API_KEY: z.string().optional(),
  // Franchise grouping is schema-constrained classification at temperature 0 — a "flash"-tier
  // model handles it as well as a frontier model at a fraction of the price. Flash Lite is the
  // default for the interactive search path and the daily bulk cron; the pricier escalate tier
  // is reserved for the genuinely ambiguous side-story splits (see groupingTier()).
  OPENROUTER_MODEL: z.string().default('google/gemini-3.1-flash-lite'),
  OPENROUTER_MODEL_BULK: z.string().default('google/gemini-3.1-flash-lite'),
  OPENROUTER_MODEL_ESCALATE: z.string().default('anthropic/claude-haiku-4.5'),
  GROUPING_LLM_DISABLED: envBool(false),

  // Cerebras hosts very-fast OpenAI-compatible inference (gpt-oss-120b) at a fraction of
  // frontier-model cost. When set it's the default for BOTH franchise grouping (preferred over
  // OpenRouter) and spell-correcting a search that returned nothing from AniList (AniList ANDs
  // query tokens with no typo tolerance, so one misspelled word zeroes the whole search).
  CEREBRAS_API_KEY: z.string().optional(),
  CEREBRAS_MODEL: z.string().default('gpt-oss-120b'),
  SEARCH_CORRECT_DISABLED: envBool(false),

  TRENDING_SEED_COUNT: z.coerce.number().default(300),

  // Announcement/news research agent (Claude Agent SDK, web tools only). Runs daily over
  // subscribed franchises; writes franchise.upcoming + announcement rows and fans out
  // notifications to subscribers. Auth: rides the machine's Claude Code login (Max
  // subscription) — ANTHROPIC_API_KEY is deliberately stripped from the agent subprocess.
  NEWS_AGENT_DISABLED: envBool(false),
  NEWS_AGENT_MODEL: z.string().optional(), // unset → the Agent SDK's default model
  NEWS_AGENT_MAX_TURNS: z.coerce.number().default(16),
  NEWS_AGENT_TIMEOUT_MS: z.coerce.number().default(300_000),
  NEWS_MAX_FRANCHISES_PER_RUN: z.coerce.number().default(25),
  NEWS_CHECK_INTERVAL_HOURS: z.coerce.number().default(20),

  // TMDB v4 read access token (Bearer). Powers the general-TV source; when unset, TV
  // search/sync is silently disabled and the app is anime-only (same spirit as
  // GROUPING_LLM_DISABLED: absence degrades, never crashes).
  TMDB_ACCESS_TOKEN: z.string().optional(),
})

export const env = schema.parse(process.env)
export type Env = z.infer<typeof schema>
