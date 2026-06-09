import { Socket } from "phoenix"
import { createMusubi } from "@musubi/react"

export const SOCKET_URL = "ws://127.0.0.1:4010/socket"

// Phoenix's JS client looks for a WebSocket transport; in Bun/Node it is the
// global WebSocket, so pass it explicitly rather than relying on `window`.
export const socket = new Socket(SOCKET_URL, { transport: WebSocket })

export const TRACE_ROOT = {
  module: "Server.Stores.TraceStore",
  id: "trace",
  params: {
    target: process.env.REDBUG_TARGET ?? "target@127.0.0.2",
    cookie: process.env.REDBUG_COOKIE ?? "poc",
    pattern: process.env.REDBUG_PATTERN ?? "lists:seq -> return"
  }
} as const

export const {
  connect,
  MusubiProvider,
  useMusubiConnection,
  useMusubiRoot,
  useMusubiSnapshot
} = createMusubi<Musubi.Stores>()
