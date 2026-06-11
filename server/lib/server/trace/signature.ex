defmodule Server.Trace.Signature do
  @moduledoc """
  Compiled-trace signature: a hash over the enabled patterns plus the redbug
  stop limits (`time`/`msgs`). Used to detect drift between a running trace and
  the current (edited) config — `Server.Stores.SessionRoot` compares the live
  runner's applied signature against the config's; a mismatch is "dirty".

  `keep` is deliberately excluded: it caps the TUI-side buffer only and never
  reaches redbug, so changing it must not require a restart.
  """

  @doc "Signature over a session's traces (only the enabled ones count) and limits."
  def compute(traces, limits) do
    enabled = traces |> Enum.filter(& &1.enabled) |> Enum.map(& &1.text)
    :erlang.phash2({enabled, limits.time, limits.msgs})
  end
end
