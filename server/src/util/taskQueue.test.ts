import { describe, expect, it } from 'vitest'
import { BoundedTaskQueue } from './taskQueue.js'

function deferred() {
  let resolve!: () => void
  const promise = new Promise<void>((done) => {
    resolve = done
  })
  return { promise, resolve }
}

describe('BoundedTaskQueue', () => {
  it('single-flights duplicate keys', async () => {
    const gate = deferred()
    let runs = 0
    const queue = new BoundedTaskQueue(1, 4)
    const first = queue.enqueue('same', async () => {
      runs++
      await gate.promise
    })
    const duplicate = queue.enqueue('same', async () => {
      runs++
    })

    expect(first.accepted).toBe(true)
    expect(first.shared).toBe(false)
    expect(duplicate.accepted).toBe(true)
    expect(duplicate.shared).toBe(true)
    expect(duplicate.done).toBe(first.done)
    gate.resolve()
    await duplicate.done
    expect(runs).toBe(1)
  })

  it('drops excess work instead of building an unbounded backlog', async () => {
    const firstGate = deferred()
    const secondGate = deferred()
    const queue = new BoundedTaskQueue(1, 2)
    const first = queue.enqueue('one', () => firstGate.promise)
    const second = queue.enqueue('two', () => secondGate.promise)
    const excess = queue.enqueue('three', async () => undefined)

    expect(queue.pendingCount).toBe(2)
    expect(excess).toMatchObject({ accepted: false, shared: false })
    await excess.done

    firstGate.resolve()
    await first.done
    secondGate.resolve()
    await second.done
    expect(queue.pendingCount).toBe(0)
  })

  it('never exceeds its active concurrency', async () => {
    const gates = [deferred(), deferred(), deferred(), deferred()]
    const queue = new BoundedTaskQueue(2, 4)
    let active = 0
    let maximum = 0
    const tasks = gates.map((gate, index) =>
      queue.enqueue(String(index), async () => {
        active++
        maximum = Math.max(maximum, active)
        await gate.promise
        active--
      }),
    )

    // Let the two queue workers enter their jobs.
    await Promise.resolve()
    await Promise.resolve()
    expect(queue.activeCount).toBe(2)
    gates[0]!.resolve()
    gates[1]!.resolve()
    await Promise.all([tasks[0]!.done, tasks[1]!.done])
    gates[2]!.resolve()
    gates[3]!.resolve()
    await Promise.all(tasks.map((task) => task.done))
    expect(maximum).toBe(2)
  })

  it('reports background errors but keeps task promises handled', async () => {
    const errors: string[] = []
    const queue = new BoundedTaskQueue(1, 2, (key) => errors.push(key))
    const task = queue.enqueue('broken', async () => {
      throw new Error('boom')
    })
    await expect(task.done).resolves.toBeUndefined()
    expect(errors).toEqual(['broken'])
  })
})
