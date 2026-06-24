// Cerebras hosts very-fast OpenAI-compatible chat inference. Both franchise grouping and search
// query correction POST to the same endpoint with the same auth — so the URL and header
// construction live here, in one place. Callers own their own request body, response parsing, and
// error handling (the grouper throws on a bad status; query correction degrades to null), so this
// deliberately returns the raw Response rather than abstracting those divergent concerns.
const CEREBRAS_CHAT_URL = 'https://api.cerebras.ai/v1/chat/completions'

export function cerebrasChat(
  apiKey: string,
  body: Record<string, unknown>,
  signal?: AbortSignal,
): Promise<Response> {
  return fetch(CEREBRAS_CHAT_URL, {
    method: 'POST',
    headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
    signal,
  })
}
