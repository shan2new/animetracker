/**
 * Compose a caller cancellation signal with a per-operation timeout. Node's fetch understands
 * AbortSignal directly, so cancellation reaches the socket instead of merely abandoning the
 * Promise that is waiting for it.
 */
export function withTimeout(parent: AbortSignal | undefined, timeoutMs: number): AbortSignal {
  const timeout = AbortSignal.timeout(Math.max(1, timeoutMs))
  return parent ? AbortSignal.any([parent, timeout]) : timeout
}

/** Sleep that stops immediately when the owning request is cancelled. */
export function abortableSleep(ms: number, signal?: AbortSignal): Promise<void> {
  if (!signal) return new Promise((resolve) => setTimeout(resolve, ms))
  if (signal.aborted) return Promise.reject(abortReason(signal))

  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      signal.removeEventListener('abort', onAbort)
      resolve()
    }, ms)
    const onAbort = () => {
      clearTimeout(timer)
      signal.removeEventListener('abort', onAbort)
      reject(abortReason(signal))
    }
    signal.addEventListener('abort', onAbort, { once: true })
  })
}

/** Preserve the platform's TimeoutError/AbortError where possible for useful diagnostics. */
export function abortReason(signal: AbortSignal): Error {
  return signal.reason instanceof Error ? signal.reason : new DOMException('Aborted', 'AbortError')
}

export function isAbortError(error: unknown): boolean {
  return error instanceof Error && (error.name === 'AbortError' || error.name === 'TimeoutError')
}
