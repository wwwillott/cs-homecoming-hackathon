import { describe, expect, it } from 'vitest'

import { PendingAudioBuffer } from './streaming-client'

function chunk(sequence: number) {
  return { sequence, pcm: new ArrayBuffer(3_200) }
}

describe('PendingAudioBuffer', () => {
  it('drops the oldest chunks when its memory bound is reached', () => {
    const buffer = new PendingAudioBuffer(2)

    expect(buffer.add(chunk(0))).toBe(0)
    expect(buffer.add(chunk(1))).toBe(0)
    expect(buffer.add(chunk(2))).toBe(1)
    expect(buffer.values().map((value) => value.sequence)).toEqual([1, 2])
  })

  it('removes acknowledged chunks', () => {
    const buffer = new PendingAudioBuffer()
    buffer.add(chunk(4))
    buffer.add(chunk(5))

    buffer.acknowledge(4)

    expect(buffer.values().map((value) => value.sequence)).toEqual([5])
  })
})
