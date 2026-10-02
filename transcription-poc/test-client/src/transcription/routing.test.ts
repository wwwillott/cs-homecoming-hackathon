import { describe, expect, it } from 'vitest'

import { transcriptionOrder } from './routing'

describe('transcriptionOrder', () => {
  it('tries the phone before cloud in auto mode', () => {
    expect(transcriptionOrder('auto', true)).toEqual(['local', 'cloud'])
  })

  it('skips local transcription when the browser cannot support it', () => {
    expect(transcriptionOrder('auto', false)).toEqual(['cloud'])
  })

  it('honors explicit routes', () => {
    expect(transcriptionOrder('local', false)).toEqual(['local'])
    expect(transcriptionOrder('cloud', true)).toEqual(['cloud'])
  })
})
