class PcmCaptureProcessor extends AudioWorkletProcessor {
  constructor() {
    super()
    this.ratio = sampleRate / 16000
    this.position = 0
    this.previous = 0
    this.output = new Int16Array(1600)
    this.outputIndex = 0
  }

  process(inputs) {
    const input = inputs[0]?.[0]
    if (!input?.length) return true

    const source = new Float32Array(input.length + 1)
    source[0] = this.previous
    source.set(input, 1)
    let position = this.position
    while (position + 1 < source.length) {
      const index = Math.floor(position)
      const fraction = position - index
      const sample = source[index] + (source[index + 1] - source[index]) * fraction
      const clipped = Math.max(-1, Math.min(1, sample))
      this.output[this.outputIndex++] =
        clipped < 0 ? Math.round(clipped * 0x8000) : Math.round(clipped * 0x7fff)
      if (this.outputIndex === this.output.length) {
        this.port.postMessage(this.output.buffer, [this.output.buffer])
        this.output = new Int16Array(1600)
        this.outputIndex = 0
      }
      position += this.ratio
    }
    this.position = position - input.length
    this.previous = input[input.length - 1]
    return true
  }
}

registerProcessor('pcm-capture', PcmCaptureProcessor)
