defmodule Server.Schema.TraceEvent do
  @moduledoc """
  One cooked redbug trace row sent to the TUI. `kind` is call/retn/send/recv,
  or the synthetic `restart` used as a "── restarted HH:MM:SS ──" separator.
  """

  use Musubi.State

  state do
    field(:id, String.t())
    field(:kind, String.t())
    field(:pid, String.t())
    field(:name, String.t())
    field(:mfa, String.t())
    field(:info, String.t())
    field(:ts, String.t())
  end
end
