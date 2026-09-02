export interface EnqueuedTask {
  /** False means the bounded queue was full and deliberately rejected new background work. */
  accepted: boolean
  /** True when this key was already queued/running and the caller joined the existing task. */
  shared: boolean
  /** Always resolves: background failures are reported through `onError`, never left unhandled. */
  done: Promise<void>
}

interface Job {
  key: string
  run: () => Promise<void>
  finish: () => void
}

/**
 * A small in-process background queue with both backpressure and single-flight semantics.
 * Search enrichment is opportunistic cache warming; it must never create an unbounded backlog
 * just because someone typed quickly or an upstream provider slowed down.
 */
export class BoundedTaskQueue {
  private active = 0
  private readonly waiting: Job[] = []
  private readonly pending = new Map<string, Promise<void>>()

  constructor(
    private readonly concurrency: number,
    private readonly capacity: number,
    private readonly onError?: (key: string, error: unknown) => void,
  ) {
    if (concurrency < 1) throw new Error('queue concurrency must be at least 1')
    if (capacity < concurrency) throw new Error('queue capacity must be at least its concurrency')
  }

  enqueue(key: string, run: () => Promise<void>): EnqueuedTask {
    const existing = this.pending.get(key)
    if (existing) return { accepted: true, shared: true, done: existing }
    if (this.pending.size >= this.capacity) {
      return { accepted: false, shared: false, done: Promise.resolve() }
    }

    let finish!: () => void
    const done = new Promise<void>((resolve) => {
      finish = resolve
    })
    this.pending.set(key, done)
    this.waiting.push({ key, run, finish })
    this.drain()
    return { accepted: true, shared: false, done }
  }

  get activeCount(): number {
    return this.active
  }

  get pendingCount(): number {
    return this.pending.size
  }

  private drain(): void {
    while (this.active < this.concurrency && this.waiting.length > 0) {
      const job = this.waiting.shift()!
      this.active++
      void Promise.resolve()
        .then(job.run)
        .catch((error) => this.onError?.(job.key, error))
        .finally(() => {
          this.active--
          this.pending.delete(job.key)
          job.finish()
          this.drain()
        })
    }
  }
}
