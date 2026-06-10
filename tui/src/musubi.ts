import { Socket } from "phoenix"
import { createMusubi } from "@musubi/react"

export const SOCKET_URL = "ws://127.0.0.1:4010/socket"

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
