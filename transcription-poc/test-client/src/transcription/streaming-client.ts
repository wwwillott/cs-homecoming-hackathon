export type StreamEvent = {
  type: 'ready' | 'ack' | 'interim' | 'final' | 'reconnecting' | 'gap' | 'error' | 'complete'
  text?: string
  sequence?: number
  session_id?: string
  message?: string
}

type BufferedChunk = { sequence: number; pcm: ArrayBuffer }

export class PendingAudioBuffer {
  private chunks: BufferedChunk[] = []
  readonly maxChunks: number

  constructor(maxChunks = 600) {
    this.maxChunks = maxChunks
  }

  add(chunk: BufferedChunk): number {
    this.chunks.push(chunk)
    const dropped = Math.max(0, this.chunks.length - this.maxChunks)
    if (dropped) this.chunks.splice(0, dropped)
    return dropped
  }

  acknowledge(sequence: number): void {
    this.chunks = this.chunks.filter((chunk) => chunk.sequence !== sequence)
  }

  values(): readonly BufferedChunk[] {
    return this.chunks
  }

  clear(): void {
    this.chunks = []
  }
}

export function websocketUrl(apiUrl: string): string {
  const base = apiUrl || window.location.origin
  const url = new URL('/api/transcriptions/stream', base)
  url.protocol = url.protocol === 'https:' ? 'wss:' : 'ws:'
  return url.toString()
}

export class StreamingTranscriber {
  private socket?: WebSocket
  private reconnectTimer?: number
  private sequence = 0
  private active = false
  private stopping = false
  private gapCount = 0
  private sessionId?: string
  private completion?: { promise: Promise<void>; resolve: () => void }
  private readonly url: string
  private readonly onEvent: (event: StreamEvent) => void
  readonly pending: PendingAudioBuffer

  constructor(
    url: string,
    onEvent: (event: StreamEvent) => void,
    maxBufferedChunks = 600,
  ) {
    this.url = url
    this.onEvent = onEvent
    this.pending = new PendingAudioBuffer(maxBufferedChunks)
  }

  get currentSessionId(): string | undefined {
    return this.sessionId
  }

  async start(personId?: string): Promise<void> {
    this.active = true
    this.stopping = false
    let resolveCompletion = (): void => undefined
    const promise = new Promise<void>((resolve) => {
      resolveCompletion = resolve
    })
    this.completion = { promise, resolve: resolveCompletion }
    await this.connect(personId)
  }

  send(pcm: ArrayBuffer): void {
    if (!this.active || pcm.byteLength === 0) return
    const chunk = { sequence: this.sequence++, pcm }
    const dropped = this.pending.add(chunk)
    if (dropped) {
      this.gapCount += dropped
      this.onEvent({
        type: 'gap',
        message: `Dropped ${dropped} old audio chunk(s) while disconnected.`,
      })
    }
    if (this.socket?.readyState === WebSocket.OPEN) this.sendChunk(chunk)
  }

  async stop(): Promise<void> {
    if (!this.active) return
    this.stopping = true
    if (this.socket?.readyState === WebSocket.OPEN) {
      if (this.gapCount) {
        this.socket.send(JSON.stringify({ type: 'gap', count: this.gapCount }))
        this.gapCount = 0
      }
      this.socket.send(JSON.stringify({ type: 'stop' }))
    }
    await Promise.race([
      this.completion?.promise ?? Promise.resolve(),
      new Promise<void>((resolve) => window.setTimeout(resolve, 10_000)),
    ])
    this.close()
  }

  close(): void {
    this.active = false
    if (this.reconnectTimer !== undefined) window.clearTimeout(this.reconnectTimer)
    this.socket?.close()
    this.socket = undefined
  }

  private connect(personId?: string): Promise<void> {
    return new Promise((resolve, reject) => {
      const socket = new WebSocket(this.url)
      socket.binaryType = 'arraybuffer'
      this.socket = socket

      socket.addEventListener('open', () => {
        socket.send(
          JSON.stringify({
            type: 'start',
            session_id: this.sessionId,
            person_id: personId,
          }),
        )
      })
      socket.addEventListener('message', (message) => {
        const event = JSON.parse(String(message.data)) as StreamEvent
        if (event.type === 'ready') {
          this.sessionId = event.session_id
          for (const chunk of this.pending.values()) this.sendChunk(chunk)
          if (this.gapCount) {
            socket.send(JSON.stringify({ type: 'gap', count: this.gapCount }))
            this.gapCount = 0
          }
          resolve()
        } else if (event.type === 'ack' && event.sequence !== undefined) {
          this.pending.acknowledge(event.sequence)
        } else if (event.type === 'complete') {
          this.completion?.resolve()
        }
        this.onEvent(event)
      })
      socket.addEventListener('error', () => {
        if (!this.sessionId) reject(new Error('Could not open the transcription stream.'))
      })
      socket.addEventListener('close', () => {
        if (this.active && !this.stopping) {
          this.onEvent({ type: 'reconnecting', message: 'Connection lost; retrying…' })
          this.reconnectTimer = window.setTimeout(() => {
            void this.connect(personId)
          }, 1_000)
        }
      })
    })
  }

  private sendChunk(chunk: BufferedChunk): void {
    if (this.socket?.readyState !== WebSocket.OPEN) return
    const frame = new ArrayBuffer(4 + chunk.pcm.byteLength)
    const view = new DataView(frame)
    view.setUint32(0, chunk.sequence, true)
    new Uint8Array(frame, 4).set(new Uint8Array(chunk.pcm))
    this.socket.send(frame)
  }
}
