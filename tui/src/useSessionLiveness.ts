import { useEffect, useRef, useState } from "react"
import { SPARK_N } from "./sessionTypes"
import type { TraceEvent } from "./types"

export function useSessionLiveness(
  running: boolean,
  events: TraceEvent[],
  timeLimit: number
): { remainingSec: number | null; buckets: number[] } {
  const lastEventAt = useRef(Date.now())
  const seenMaxId = useRef(0)
  const [nowTick, setNowTick] = useState(() => Date.now())
  const runningSince = useRef<number | null>(null)

  if (running && runningSince.current === null) runningSince.current = nowTick
  if (!running && runningSince.current !== null) runningSince.current = null

  const remainingSec =
    running && runningSince.current !== null
      ? Math.max(0, timeLimit - Math.floor((nowTick - runningSince.current) / 1000))
      : null

  const curMaxId = events.reduce((m, e) => Math.max(m, Number(e.id)), seenMaxId.current)
  if (curMaxId > seenMaxId.current) {
    lastEventAt.current = Date.now()
    seenMaxId.current = curMaxId
  }

  // Rate sparkline: per-second arrivals over a rolling window.
  const eventsRef = useRef(events)
  eventsRef.current = events
  const lastMaxId = useRef(0)
  const buckets = useRef<number[]>(new Array(SPARK_N).fill(0))

  useEffect(() => {
    if (!running) {
      buckets.current = new Array(SPARK_N).fill(0)
      return
    }
    const id = setInterval(() => {
      let delta = 0
      let mx = lastMaxId.current
      for (const e of eventsRef.current) {
        const n = Number(e.id)
        if (n > lastMaxId.current) delta++
        if (n > mx) mx = n
      }
      lastMaxId.current = mx
      buckets.current = [...buckets.current.slice(1), delta]
      setNowTick(Date.now())
    }, 1000)
    return () => clearInterval(id)
  }, [running])

  return { remainingSec, buckets: buckets.current }
}
