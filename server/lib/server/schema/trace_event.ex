defmodule Server.Schema.TraceEvent do
  @moduledoc """
  One cooked redbug trace row sent to the TUI. `kind` is call/retn/send/recv,
  or the synthetic `restart` used as a "── restarted HH:MM:SS ──" separator.

  A `call` traced with `-> return` and its `retn` are separate events that share
  the same `pair` id (so the TUI can link/fold them) and carry the call `depth`
  (per-pid nesting level) for indentation. send/recv/restart have an empty
  `pair` and depth 0.
  """

  @type t :: %__MODULE__{
          id: String.t(),
          kind: String.t(),
          pid: String.t(),
          name: String.t(),
          mfa: String.t(),
          info: String.t(),
          pair: String.t(),
          depth: integer(),
          ts: String.t()
        }

  defstruct [:id, :kind, :pid, :name, :mfa, :info, :pair, :depth, :ts]
end
