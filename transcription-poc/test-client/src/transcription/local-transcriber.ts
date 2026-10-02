export type TranscriptSegment = {
  start_seconds: number
  end_seconds: number
  text: string
}

export type TranscriptionResult = {
  transcript: string
  segments: TranscriptSegment[]
  provider: string
  language: string | null
}

type WorkerResponse =
  | { type: 'ready'; requestId: string }
  | { type: 'result'; requestId: string; result: TranscriptionResult }
  | { type: 'error'; requestId: string; error: string }
  | { type: 'progress'; progress: number; status: string }

type PendingRequest = {
  resolve: (value: TranscriptionResult | undefined) => void
  reject: (reason: Error) => void
}

export class LocalTranscriber {
  private worker: Worker
  private pending = new Map<string, PendingRequest>()
  private progressCallback?: (progress: number, status: string) => void

  constructor(onProgress?: (progress: number, status: string) => void) {
    this.progressCallback = onProgress
    this.worker = this.createWorker()
  }

  static isSupported(): boolean {
    return (
      typeof Worker !== 'undefined' &&
      typeof WebAssembly !== 'undefined' &&
      typeof AudioContext !== 'undefined' &&
      typeof OfflineAudioContext !== 'undefined'
    )
  }

  async initialize(): Promise<void> {
    if (!LocalTranscriber.isSupported()) {
      throw new Error('This browser cannot run local transcription.')
    }
    const requestId = crypto.randomUUID()
    await new Promise<void>((resolve, reject) => {
      this.pending.set(requestId, {
        resolve: () => resolve(),
        reject,
      })
      this.worker.postMessage({ type: 'initialize', requestId })
    })
  }

  async transcribe(blob: Blob): Promise<TranscriptionResult> {
    const samples = await decodeAndResample(blob)
    const requestId = crypto.randomUUID()

    return new Promise<TranscriptionResult>((resolve, reject) => {
      this.pending.set(requestId, {
        resolve: (result) => {
          if (!result) {
            reject(new Error('Local transcription returned no result.'))
            return
          }
          resolve(result)
        },
        reject,
      })
      this.worker.postMessage(
        { type: 'transcribe', requestId, audio: samples },
        [samples.buffer],
      )
    })
  }

  cancel(): void {
    for (const request of this.pending.values()) {
      request.reject(new Error('Local transcription was cancelled.'))
    }
    this.pending.clear()
    this.worker.terminate()
    this.worker = this.createWorker()
  }

  dispose(): void {
    this.cancel()
    this.worker.terminate()
  }

  private createWorker(): Worker {
    const worker = new Worker(
      new URL('./local-whisper.worker.ts', import.meta.url),
      { type: 'module' },
    )
    worker.addEventListener('message', (event: MessageEvent<WorkerResponse>) => {
      const message = event.data
      if (message.type === 'progress') {
        this.progressCallback?.(message.progress, message.status)
        return
      }

      const request = this.pending.get(message.requestId)
      if (!request) return
      this.pending.delete(message.requestId)

      if (message.type === 'error') {
        request.reject(new Error(message.error))
      } else if (message.type === 'result') {
        request.resolve(message.result)
      } else {
        request.resolve(undefined)
      }
    })
    worker.addEventListener('error', (event) => {
      const error = new Error(event.message || 'The transcription worker crashed.')
      for (const request of this.pending.values()) request.reject(error)
      this.pending.clear()
    })
    return worker
  }
}

async function decodeAndResample(blob: Blob): Promise<Float32Array> {
  const context = new AudioContext()
  try {
    const decoded = await context.decodeAudioData(await blob.arrayBuffer())
    const frameCount = Math.ceil(decoded.duration * 16_000)
    const offline = new OfflineAudioContext(1, frameCount, 16_000)
    const source = offline.createBufferSource()
    source.buffer = decoded
    source.connect(offline.destination)
    source.start()
    const rendered = await offline.startRendering()
    return new Float32Array(rendered.getChannelData(0))
  } finally {
    await context.close()
  }
}
