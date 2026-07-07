// Simple fuzzy matcher: returns true if all characters of `query` appear in
// `target` in order (case-insensitive). Used by DialogSelect for filtering.
export function fuzzyMatch(query: string, target: string): boolean {
  if (query === "") return true
  let qi = 0
  const q = query.toLowerCase()
  const t = target.toLowerCase()
  for (let i = 0; i < t.length && qi < q.length; i++) {
    if (t[i] === q[qi]) qi++
  }
  return qi === q.length
}

// Score a match: length of the target matched substrings (higher = better).
// Used to sort filtered items so the best matches appear first.
export function fuzzyScore(query: string, target: string): number {
  if (query === "") return 0
  const q = query.toLowerCase()
  const t = target.toLowerCase()
  let score = 0
  let qi = 0
  let run = 0
  for (let i = 0; i < t.length && qi < q.length; i++) {
    if (t[i] === q[qi]) {
      run++
      qi++
    } else if (run > 0) {
      score += run * run
      run = 0
    }
  }
  if (run > 0) score += run * run
  return score
}
