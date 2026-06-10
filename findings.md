# Findings — redbug-cli formal build

## musubi API (verified from server/deps/musubi/lib, 2026-06-09)

### Stores
- `use Musubi.Store, root: true` — only option is `root:`. Root stores get default `mount/2`,
  are socket-addressable. Child stores use `init/1` instead (mount/2 on non-root = compile error).
- Callbacks: `render/1` + `handle_command/3` required; `mount/2` (root), `init/1` (child),
  `update/2`, `handle_info/2`, `handle_async/3`, `terminate/2` optional.
- `use` imports runtime helpers: assign, stream*, child, async.

### State DSL (`state do ... end`)
- `field(name, type, opts)` — opts → TypedStructor; `default:` supported. Nested `field name do … end` inline map forbids opts.
- `stream(name, item_type, opts)` — opts `item_key:` (arity-1 fn → binary, default `&"name-#{&1.id}"`), `limit:` (int|nil).
- `attr(name, type, opts)` — parent-supplied assigns; `required:`, `default:`.
- Reusable state via `use Musubi.State`.

### Child / nested stores — SUPPORTED (this is our Node▸Session mechanism)
- In `render/1`: `child(Module, id: "x", <assigns>)`. Opts: `id:` (binary local id) + arbitrary keys flowed as child assigns.
- Runtime identity = parent_path ++ [id] (array of strings = store_id), echoed by client on commands.
- Child re-renders only if consumed assign keys changed (memoized). Sibling ids must be unique.
- Field holding a child typed `Module.state()` → TS `StoreField<"Full.Module">`.
- Arbitrary nesting depth.

### Commands & inputs
- `command :name do payload do field … end; reply do field … end end`. Field opt: only `:doc`. `musubi:` names reserved.
- Handler: `handle_command(name, payload, socket)` → `{:noreply, socket}` | `{:reply, map, socket}`.
- `use Musubi.Input` + `input do field … end` for input objects (fields only).
- No generated TS *call* code; codegen emits ambient `.d.ts` (`StoreDef<Module, Shape, Commands>` with typed payload/reply). Runtime via `@musubi/client connect<R>()` / `@musubi/react createMusubi<R>()`.

### Socket roots
- `use Musubi.Socket, roots: [Store1, Store2, ...]`; each must be `root: true`.
- Client addresses root by module string + mount params. Root store_id = `[]`.

### Stream ops (server queues ops; CLIENT materializes/orders/trims)
- `stream(socket, name, items, reset: true)`
- `stream_insert(socket, name, item, at: -1|0|n, limit: n)`
- `stream_configure(socket, name, item_key:, limit:)` — before init.
- `stream_delete(socket, name, item)` / `stream_delete_by_item_key(socket, name, key)`
- Each op carries its store_id → routed to the right child store.

## Architecture verdict (REVISED 2026-06-09 per user)
- **Data lives in ETS** (owned by `Server.Config` GenServer) = single source of truth.
  Stores read ETS directly (`:ets.lookup`, fast, no GenServer call) + subscribe PubSub
  `"config"` topic; on `{:config_updated}` broadcast they re-read ETS, reassign, re-render.
- **`Server.Config` GenServer** serializes writes: every mutation → write ETS + persist
  JSON (0600) + PubSub broadcast. Read helpers are plain module funcs hitting ETS.
- **Side-effects (remote node) go through the GenServer, NOT the store.** `Node.connect`,
  later `:redbug`, run inside GenServer/session-runner procs. Store `handle_command`
  only forwards intent (call/cast) to the GenServer.
- **3 root stores** on one socket: `NodesRoot` (node tree), `PresetsRoot`, `SettingsRoot`.
- P1 = flat projection: each root reads its ETS slice, returns nested data. Child stores
  deferred to P2 (SessionStore-as-child earns its keep when it owns the event stream;
  events buffered by a runner GenServer → store emits via stream).
- ETS keys: `:nodes`, `:presets`, `:settings` (persisted) + `:connected` (MapSet node ids),
  `:session_status` (runtime, not persisted). Store merges runtime into wire shape.
- Mutations = musubi `command`s → forward to `Server.Config`. View ops (sort/filter/group)
  = client-side only, no server round-trip.

## redbug constraints (verified earlier, server/deps/redbug/src/redbug.erl)
- Singleton per target: registers `redbug_<target>`; already-running → `redbug_already_started`.
- Patterns compiled at start; NO hot-add. Change pattern = stop + start.
- `stop()` = `stop(node())` — for remote must call `stop(target_node)`. `stop/1` async (sends msg, returns).
- `start(Trc, Opts)` returns `{nprocs, nfuncs}` local or `{node, nprocs, nfuncs}` remote; else error atom.
- ts is `{h,m,s,us}` → ms via `us div 1000`.
- One running redbug session per target node (enforces "one running session per node").

## Existing PoC code (baseline to reshape)
- server/lib/server/stores/trace_store.ex — single root store, async start, stop+wait+start idempotent.
- server/lib/server/trace_event.ex — TraceEvent state (id/kind/pid/name/mfa/info/ts).
- server/lib/server_web/user_socket.ex — `use Musubi.Socket, roots: [TraceStore]`.
- server/lib/server/application.ex — `ensure_distributed/0` longname controller.
- tui/src/{App.tsx,index.tsx,musubi.ts} — single TRACE_ROOT, event list + detail.
- Config: endpoint 4010; musubi ts codegen → tui/src/generated/musubi.d.ts.

## Open design refs
- Full screen spec: docs/screens.md (7 screens, CONFIRMED).
</content>
