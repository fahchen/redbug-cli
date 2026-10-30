defmodule Server.Dist do
  @moduledoc """
  The distribution switch. `REDBUG_DIST=off` starts the controller without
  distribution: no `net_kernel`, no node monitor, and each connect fails with
  `:distribution_off`. The local stores, sessions, presets, and snippets still
  work. Any other value, or no value, keeps distribution on.

  The switch lets the controller run on a VM that has no distribution yet
  (PBeam). Remove it when that VM has distribution.
  """

  @spec enabled?() :: boolean()
  def enabled?, do: System.get_env("REDBUG_DIST") != "off"
end
