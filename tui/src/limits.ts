export type Limits = { keep: number; time: number; msgs: number }

export const DEFAULT_LIMITS: Limits = { keep: 500, time: 900, msgs: 10000 }

// "keep time msgs", space-separated — the format every limits input accepts.
export function formatLimits(l: Limits): string {
  return `${l.keep} ${l.time} ${l.msgs}`
}

export function parseLimits(s: string): Limits | null {
  const parts = s.trim().split(/\s+/).map(Number)
  if (parts.length !== 3 || parts.some((x) => !Number.isFinite(x) || x < 0)) return null
  return { keep: parts[0], time: parts[1], msgs: parts[2] }
}
