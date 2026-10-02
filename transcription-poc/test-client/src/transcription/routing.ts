export type TranscriptionMode = 'auto' | 'local' | 'cloud'
export type TranscriptionRoute = 'local' | 'cloud'

export function transcriptionOrder(
  mode: TranscriptionMode,
  localSupported: boolean,
): TranscriptionRoute[] {
  if (mode === 'cloud') return ['cloud']
  if (mode === 'local') return ['local']
  return localSupported ? ['local', 'cloud'] : ['cloud']
}
