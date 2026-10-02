/// <reference lib="webworker" />

import { env, pipeline } from '@huggingface/transformers'

import type {
  TranscriptSegment,
  TranscriptionResult,
} from './local-transcriber'

type RequestMessage =
  | { type: 'initialize'; requestId: string }
  | { type: 'transcribe'; requestId: string; audio: Float32Array }

type WhisperOutput = {
  text: string
  chunks?: Array<{
    text: string
    timestamp: [number | null, number | null]
  }>
}

type Transcriber = (
  audio: Float32Array,
  options: Record<string, unknown>,
) => Promise<WhisperOutput>

const worker = self as unknown as DedicatedWorkerGlobalScope
env.allowLocalModels = false

let transcriberPromise: Promise<Transcriber> | undefined

function loadTranscriber(): Promise<Transcriber> {
  if (!transcriberPromise) {
    const device = 'gpu' in worker.navigator ? 'webgpu' : 'wasm'
    transcriberPromise = pipeline(
      'automatic-speech-recognition',
      'onnx-community/whisper-tiny.en',
      {
        device,
        progress_callback: (event: {
          progress?: number
          status?: string
          file?: string
        }) => {
          worker.postMessage({
            type: 'progress',
            progress: event.progress ?? 0,
            status: event.file
              ? `${event.status ?? 'loading'} ${event.file}`
              : (event.status ?? 'loading model'),
          })
        },
      },
    ) as unknown as Promise<Transcriber>
  }
  return transcriberPromise
}

worker.addEventListener('message', async (event: MessageEvent<RequestMessage>) => {
  const message = event.data
  try {
    const transcriber = await loadTranscriber()
    if (message.type === 'initialize') {
      worker.postMessage({ type: 'ready', requestId: message.requestId })
      return
    }

    const output = await transcriber(message.audio, {
      chunk_length_s: 20,
      stride_length_s: 4,
      return_timestamps: true,
    })
    const transcript = output.text.trim()
    const segments: TranscriptSegment[] = (output.chunks ?? [])
      .map((chunk) => ({
        start_seconds: chunk.timestamp[0] ?? 0,
        end_seconds: chunk.timestamp[1] ?? chunk.timestamp[0] ?? 0,
        text: chunk.text.trim(),
      }))
      .filter((segment) => segment.text.length > 0)

    const result: TranscriptionResult = {
      transcript,
      segments:
        segments.length > 0
          ? segments
          : [{ start_seconds: 0, end_seconds: 0, text: transcript }],
      provider: 'browser-whisper',
      language: 'en',
    }
    worker.postMessage({ type: 'result', requestId: message.requestId, result })
  } catch (error) {
    transcriberPromise = undefined
    worker.postMessage({
      type: 'error',
      requestId: message.requestId,
      error: error instanceof Error ? error.message : String(error),
    })
  }
})
