defmodule Server.Schema.Limits do
  @moduledoc """
  Trace limits for a session or preset.

  `keep` is the TUI-side event buffer cap (client trims). `time`/`msgs` are
  redbug-side stop conditions (seconds, message count).
  """

  use Musubi.State

  state do
    field(:keep, integer())
    field(:time, integer())
    field(:msgs, integer())
  end
end
