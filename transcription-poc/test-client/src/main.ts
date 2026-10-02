import './style.css'

import {
  LocalTranscriber,
  type TranscriptionResult,
} from './transcription/local-transcriber'
import {
  transcriptionOrder,
  type TranscriptionMode,
} from './transcription/routing'
import {
  StreamingTranscriber,
  type StreamEvent,
  websocketUrl,
} from './transcription/streaming-client'

type Person = { id: string; name: string }
type SavedConversation = {
  summary: { profile_suggestion: unknown }
  suggestion_id: string
}

const API_URL = import.meta.env.VITE_API_URL ?? ''

document.querySelector<HTMLDivElement>('#app')!.innerHTML = `
  <main>
    <h1>Conversation transcription test</h1>
    <p>Record a short conversation, inspect the transcript, then generate networking notes.</p>

    <section>
      <label for="person">Conversation person</label>
      <select id="person"></select>
      <div class="actions">
        <input id="new-person" placeholder="New person's name" />
        <button id="create-person">Create person</button>
      </div>
    </section>

    <section>
      <label for="mode">Transcription route</label>
      <select id="mode">
        <option value="streaming">Cloud streaming (recommended)</option>
        <option value="local">On-device batch (diagnostic)</option>
        <option value="cloud">Cloud file (diagnostic)</option>
      </select>
      <p class="hint">Streaming shows words while you speak and stores only final transcript text. Audio stays in memory and is not saved.</p>

      <div class="actions">
        <button id="record">Record</button>
        <button id="stop" disabled>Stop</button>
      </div>
      <p id="status" role="status">Ready.</p>
      <progress id="progress" max="100" value="0" hidden></progress>
    </section>

    <section>
      <label for="transcript">Transcript</label>
      <textarea id="transcript" rows="10" placeholder="Your transcript will appear here."></textarea>
      <p id="interim" class="hint" aria-live="polite"></p>
      <p id="gap-warning" class="error" hidden>Some audio was lost while the connection was unavailable.</p>
      <button id="summarize">Save conversation and summarize</button>
    </section>

    <section>
      <h2>Summary and suggested notes</h2>
      <pre id="summary">No summary yet.</pre>
      <button id="approve" hidden>Approve suggested profile updates</button>
    </section>

    <section>
      <h2>Ask your network</h2>
      <input id="question" placeholder="Who could help me learn about robotics?" />
      <div class="actions">
        <button id="ask-network">Ask</button>
        <button id="introductions">Suggest introductions</button>
      </div>
      <pre id="network-answer">No network query yet.</pre>
    </section>
  </main>
`

const recordButton = element<HTMLButtonElement>('record')
const stopButton = element<HTMLButtonElement>('stop')
const summarizeButton = element<HTMLButtonElement>('summarize')
const transcriptInput = element<HTMLTextAreaElement>('transcript')
const summaryOutput = element<HTMLPreElement>('summary')
const modeSelect = element<HTMLSelectElement>('mode')
const statusOutput = element<HTMLParagraphElement>('status')
const progress = element<HTMLProgressElement>('progress')
const personSelect = element<HTMLSelectElement>('person')
const newPersonInput = element<HTMLInputElement>('new-person')
const createPersonButton = element<HTMLButtonElement>('create-person')
const approveButton = element<HTMLButtonElement>('approve')
const questionInput = element<HTMLInputElement>('question')
const askNetworkButton = element<HTMLButtonElement>('ask-network')
const introductionsButton = element<HTMLButtonElement>('introductions')
const networkAnswer = element<HTMLPreElement>('network-answer')
const interimOutput = element<HTMLParagraphElement>('interim')
const gapWarning = element<HTMLParagraphElement>('gap-warning')

const localTranscriber = new LocalTranscriber((value, status) => {
  progress.hidden = false
  progress.value = Math.round(value)
  setStatus(`${status} ${Math.round(value)}%`)
})

let recorder: MediaRecorder | undefined
let stream: MediaStream | undefined
let chunks: Blob[] = []
let transcriptionProvider = 'unknown'
let savedConversation: SavedConversation | undefined
let streamingTranscriber: StreamingTranscriber | undefined
let audioContext: AudioContext | undefined
let workletNode: AudioWorkletNode | undefined
let streamingSessionId: string | undefined
let committedTranscript = ''

createPersonButton.addEventListener('click', async () => {
  const name = newPersonInput.value.trim()
  if (!name) {
    setStatus('Enter a name first.', true)
    return
  }
  try {
    const response = await fetch(`${API_URL}/api/people`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ name }),
    })
    const body: unknown = await response.json()
    if (!response.ok) throw new Error(apiError(body, response.status))
    newPersonInput.value = ''
    await loadPeople((body as Person).id)
    setStatus(`Created ${name}.`)
  } catch (error) {
    setStatus(errorMessage(error), true)
  }
})

recordButton.addEventListener('click', async () => {
  try {
    if (modeSelect.value === 'streaming') {
      await startStreaming()
      return
    }
    stream = await navigator.mediaDevices.getUserMedia({ audio: true })
    const mimeType = preferredMimeType()
    recorder = new MediaRecorder(stream, mimeType ? { mimeType } : undefined)
    chunks = []
    recorder.addEventListener('dataavailable', (event) => {
      if (event.data.size > 0) chunks.push(event.data)
    })
    recorder.start()
    recordButton.disabled = true
    stopButton.disabled = false
    setStatus('Recording…')
  } catch (error) {
    setStatus(errorMessage(error), true)
    streamingTranscriber?.close()
    streamingTranscriber = undefined
    releaseMicrophone()
  }
})

stopButton.addEventListener('click', async () => {
  if (streamingTranscriber) {
    stopButton.disabled = true
    releaseMicrophone()
    try {
      await streamingTranscriber.stop()
      streamingSessionId = streamingTranscriber.currentSessionId
      transcriptionProvider = 'google-cloud-speech-v2'
      setStatus('Streaming transcript completed.')
    } catch (error) {
      setStatus(errorMessage(error), true)
    } finally {
      streamingTranscriber = undefined
      recordButton.disabled = false
    }
    return
  }
  if (!recorder) return
  stopButton.disabled = true
  const recording = await stopRecorder(recorder)
  releaseMicrophone()
  recordButton.disabled = false

  try {
    const result = await transcribe(recording, modeSelect.value as TranscriptionMode)
    transcriptInput.value = result.transcript
    transcriptionProvider = result.provider
    setStatus(`Transcribed with ${result.provider}.`)
  } catch (error) {
    setStatus(errorMessage(error), true)
  } finally {
    progress.hidden = true
  }
})

summarizeButton.addEventListener('click', async () => {
  const transcript = transcriptInput.value.trim()
  if (!transcript) {
    setStatus('Record or enter a transcript first.', true)
    return
  }
  if (!personSelect.value) {
    setStatus('Create and select the person from this conversation.', true)
    return
  }

  summarizeButton.disabled = true
  setStatus('Saving conversation and generating suggestions…')
  try {
    const response = await fetch(`${API_URL}/api/conversations`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        person_id: personSelect.value,
        transcript: streamingSessionId ? undefined : transcript,
        transcription_session_id: streamingSessionId,
        provider: transcriptionProvider,
      }),
    })
    const body: unknown = await response.json()
    if (!response.ok) throw new Error(apiError(body, response.status))
    savedConversation = body as SavedConversation
    summaryOutput.textContent = JSON.stringify(savedConversation.summary, null, 2)
    approveButton.hidden = false
    setStatus('Conversation saved. Review and approve the profile suggestions.')
  } catch (error) {
    setStatus(errorMessage(error), true)
  } finally {
    summarizeButton.disabled = false
  }
})

approveButton.addEventListener('click', async () => {
  if (!savedConversation) return
  approveButton.disabled = true
  setStatus('Applying approved suggestions and indexing the person…')
  try {
    const response = await fetch(
      `${API_URL}/api/suggestions/${savedConversation.suggestion_id}/approve`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          profile: savedConversation.summary.profile_suggestion,
        }),
      },
    )
    const body: unknown = await response.json()
    if (!response.ok) throw new Error(apiError(body, response.status))
    approveButton.hidden = true
    await loadPeople(personSelect.value)
    setStatus('Profile updated and indexed.')
  } catch (error) {
    setStatus(errorMessage(error), true)
  } finally {
    approveButton.disabled = false
  }
})

askNetworkButton.addEventListener('click', async () => {
  const question = questionInput.value.trim()
  if (!question) {
    setStatus('Enter a network question first.', true)
    return
  }
  setStatus('Searching approved network information…')
  try {
    const response = await fetch(`${API_URL}/api/network/ask`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ question }),
    })
    const body: unknown = await response.json()
    if (!response.ok) throw new Error(apiError(body, response.status))
    networkAnswer.textContent = JSON.stringify(body, null, 2)
    setStatus('Network answer ready.')
  } catch (error) {
    setStatus(errorMessage(error), true)
  }
})

introductionsButton.addEventListener('click', async () => {
  setStatus('Finding introduction candidates…')
  try {
    const response = await fetch(
      `${API_URL}/api/network/introduction-suggestions`,
    )
    const body: unknown = await response.json()
    if (!response.ok) throw new Error(apiError(body, response.status))
    networkAnswer.textContent = JSON.stringify(body, null, 2)
    setStatus('Introduction candidates ready.')
  } catch (error) {
    setStatus(errorMessage(error), true)
  }
})

async function loadPeople(selectedId?: string): Promise<void> {
  const response = await fetch(`${API_URL}/api/people`)
  const body: unknown = await response.json()
  if (!response.ok) throw new Error(apiError(body, response.status))
  const people = body as Person[]
  personSelect.replaceChildren(
    ...people.map((person) => {
      const option = document.createElement('option')
      option.value = person.id
      option.textContent = person.name
      return option
    }),
  )
  if (selectedId) personSelect.value = selectedId
}

async function transcribe(
  blob: Blob,
  mode: TranscriptionMode,
): Promise<TranscriptionResult> {
  const routes = transcriptionOrder(mode, LocalTranscriber.isSupported())
  if (routes[0] === 'local') {
    try {
      setStatus('Loading the on-device model…')
      await localTranscriber.initialize()
      setStatus('Transcribing on this device…')
      return await localTranscriber.transcribe(blob)
    } catch (error) {
      if (!routes.includes('cloud')) throw error
      setStatus(`Local transcription failed; using cloud fallback. ${errorMessage(error)}`)
    }
  }

  setStatus('Uploading ephemeral audio for cloud transcription…')
  const form = new FormData()
  form.append('audio', blob, recordingFilename(blob.type))
  const response = await fetch(`${API_URL}/api/transcriptions`, {
    method: 'POST',
    body: form,
  })
  const body: unknown = await response.json()
  if (!response.ok) throw new Error(apiError(body, response.status))
  return body as TranscriptionResult
}

function stopRecorder(activeRecorder: MediaRecorder): Promise<Blob> {
  return new Promise((resolve, reject) => {
    activeRecorder.addEventListener(
      'stop',
      () => resolve(new Blob(chunks, { type: activeRecorder.mimeType })),
      { once: true },
    )
    activeRecorder.addEventListener(
      'error',
      () => reject(new Error('The browser could not finish the recording.')),
      { once: true },
    )
    activeRecorder.stop()
  })
}

function releaseMicrophone(): void {
  workletNode?.disconnect()
  workletNode = undefined
  void audioContext?.close()
  audioContext = undefined
  stream?.getTracks().forEach((track) => track.stop())
  stream = undefined
  recorder = undefined
}

async function startStreaming(): Promise<void> {
  if (!personSelect.value) {
    throw new Error('Create and select the person from this conversation first.')
  }
  stream = await navigator.mediaDevices.getUserMedia({
    audio: {
      channelCount: 1,
      echoCancellation: true,
      noiseSuppression: true,
    },
  })
  audioContext = new AudioContext()
  await audioContext.audioWorklet.addModule('/pcm-worklet.js')
  const source = audioContext.createMediaStreamSource(stream)
  workletNode = new AudioWorkletNode(audioContext, 'pcm-capture')
  const silentGain = audioContext.createGain()
  silentGain.gain.value = 0
  source.connect(workletNode)
  workletNode.connect(silentGain)
  silentGain.connect(audioContext.destination)

  committedTranscript = ''
  transcriptInput.value = ''
  interimOutput.textContent = ''
  gapWarning.hidden = true
  streamingSessionId = undefined
  streamingTranscriber = new StreamingTranscriber(
    websocketUrl(API_URL),
    handleStreamEvent,
  )
  workletNode.port.onmessage = (event: MessageEvent<ArrayBuffer>) => {
    streamingTranscriber?.send(event.data)
  }
  await streamingTranscriber.start(personSelect.value)
  recordButton.disabled = true
  stopButton.disabled = false
  setStatus('Streaming transcription is live…')
}

function handleStreamEvent(event: StreamEvent): void {
  if (event.type === 'ready') {
    streamingSessionId = event.session_id
    if (event.text) committedTranscript = event.text
  } else if (event.type === 'final' && event.text) {
    committedTranscript = `${committedTranscript} ${event.text}`.trim()
    interimOutput.textContent = ''
  } else if (event.type === 'interim') {
    interimOutput.textContent = event.text ? `Hearing: ${event.text}` : ''
  } else if (event.type === 'gap') {
    gapWarning.hidden = false
  } else if (event.type === 'reconnecting') {
    setStatus(event.message ?? 'Reconnecting to transcription…')
  } else if (event.type === 'error') {
    setStatus(event.message ?? 'Streaming transcription failed.', true)
  }
  transcriptInput.value = committedTranscript
}

function preferredMimeType(): string | undefined {
  return ['audio/webm;codecs=opus', 'audio/mp4', 'audio/webm'].find((type) =>
    MediaRecorder.isTypeSupported(type),
  )
}

function recordingFilename(mimeType: string): string {
  return mimeType.includes('mp4') ? 'conversation.m4a' : 'conversation.webm'
}

function apiError(body: unknown, status: number): string {
  if (
    typeof body === 'object' &&
    body !== null &&
    'detail' in body &&
    typeof body.detail === 'string'
  ) {
    return body.detail
  }
  return `Request failed with status ${status}.`
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error)
}

function setStatus(message: string, isError = false): void {
  statusOutput.textContent = message
  statusOutput.classList.toggle('error', isError)
}

function element<T extends HTMLElement>(id: string): T {
  const found = document.getElementById(id)
  if (!found) throw new Error(`Missing #${id}`)
  return found as T
}

void loadPeople().catch((error) => setStatus(errorMessage(error), true))
