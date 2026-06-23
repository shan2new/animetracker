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
  OPENROUTER_MODEL: z.string().default('anthropic/claude-opus-4.8'),
  OPENROUTER_MODEL_BULK: z.string().default('anthropic/claude-sonnet-4.5'),
  GROUPING_LLM_DISABLED: envBool(false),

  TRENDING_SEED_COUNT: z.coerce.number().default(300),
})

export const env = schema.parse(process.env)
export type Env = z.infer<typeof schema>
