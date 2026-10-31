defmodule Server.Schema.ConsoleExec do
  @moduledoc """
  One Console execution: a whole code block run on the target as a unit.

  `status` is one of "running" | "ok" | "error" | "stopped" | "timeout".
  `result` is the inspected return value (or error); `output` is captured
  stdout. `duration_ms` is nil while running.
  """

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          code: String.t(),
          status: String.t(),
          result: String.t(),
          output: String.t(),
          ts: String.t(),
          duration_ms: integer() | nil
        }

  defstruct [:id, :name, :code, :status, :result, :output, :ts, :duration_ms]
end
