defmodule Server.Schema.TraceEvent do
  @moduledoc """
  One cooked redbug trace row sent to the TUI. `kind` is call/retn/send/recv,
  or the synthetic `restart` used as a "── restarted HH:MM:SS ──" separator.

  A `call` traced with `-> return` and its `retn` are separate events that share
  the same `pair` id (so the TUI can link/fold them) and carry the call `depth`
  (per-pid nesting level) for indentation. send/recv/restart have an empty
  `pair` and depth 0.
  """

  use Musubi.State

  state do
    field(:id, String.t())
    field(:kind, String.t())
    field(:pid, String.t())
    field(:name, String.t())
    field(:mfa, String.t())
    field(:info, String.t())
    field(:pair, String.t())
    field(:depth, integer())
    field(:ts, String.t())
  end
end
