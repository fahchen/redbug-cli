defmodule Server.Schema.ConsoleExec do
  @moduledoc """
  One Console execution: a whole code block run on the target as a unit.

  `status` is one of "running" | "ok" | "error" | "stopped" | "timeout".
  `result` is the inspected return value (or error); `output` is captured
  stdout. `duration_ms` is nil while running.
  """

  use Musubi.State

  state do
    field(:id, String.t())
    field(:name, String.t())
    field(:code, String.t())
    field(:status, String.t())
    field(:result, String.t())
    field(:output, String.t())
    field(:ts, String.t())
    field(:duration_ms, integer() | nil)
  end
end
