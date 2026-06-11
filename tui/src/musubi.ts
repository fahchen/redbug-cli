import { Socket } from "phoenix"
import { createMusubi } from "@musubi/react"

declare const Bun: { env: Record<string, string | undefined> }
const HOST = Bun.env.REDBUG_HOST ?? "127.0.0.1"
const PORT = Bun.env.REDBUG_PORT ?? "4010"
export const SOCKET_URL = `ws://${HOST}:${PORT}/socket`

// Phoenix's JS client looks for a WebSocket transport; in Bun/Node it is the
// global WebSocket, so pass it explicitly rather than relying on `window`.
export const socket = new Socket(SOCKET_URL, { transport: WebSocket })

export const NODES_ROOT = {
  module: "Server.Stores.NodesRoot",
  id: "nodes",
  params: {}
} as const

export const PRESETS_ROOT = {
  module: "Server.Stores.PresetsRoot",
  id: "presets",
  params: {}
} as const

export const SETTINGS_ROOT = {
  module: "Server.Stores.SettingsRoot",
  id: "settings",
  params: {}
} as const

export const sessionRoot = (nodeId: string, sessionId: string) =>
  ({
    module: "Server.Stores.SessionRoot",
    id: `session:${sessionId}`,
    params: { node_id: nodeId, session_id: sessionId }
  }) as const

export const {
  connect,
  MusubiProvider,
  useMusubiConnection,
  useMusubiRoot,
  useMusubiSnapshot
} = createMusubi<Musubi.Stores>()

// Fire-and-forget command sender: dispatches are optimistic and the UI re-renders
// off pushed state, so a rejected promise is swallowed rather than thrown into React.
type Dispatchable = { dispatchCommand: (name: any, payload: any) => Promise<unknown> }

export function dispatcher<S extends Dispatchable>(store: S) {
  return (name: Parameters<S["dispatchCommand"]>[0], payload: any = {}) =>
    void store.dispatchCommand(name as any, payload).catch(() => {})
}
