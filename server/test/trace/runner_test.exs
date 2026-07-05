defmodule Server.Trace.RunnerTest do
  use ExUnit.Case, async: true

  alias Server.Trace.Runner

  test "short clean redbug exit is not reported as a time limit" do
    assert Runner.which_limit(%{
             applied_limits: %{time: 60, msgs: 100},
             started_at: System.monotonic_time(:millisecond),
             event_count: 0
           }) == nil
  end

  test "classifies message and time limits" do
    now = System.monotonic_time(:millisecond)

    assert Runner.which_limit(%{
             applied_limits: %{time: 60, msgs: 100},
             started_at: now,
             event_count: 100
           }) == "msgs"

    assert Runner.which_limit(%{
             applied_limits: %{time: 60, msgs: 100},
             started_at: now - 60_000,
             event_count: 0
           }) == "time"
  end

  test "stack traces raise redbug max message size" do
    assert Runner.stack_opts([%{text: "Date.shift/2 -> return;stack"}]) == [
             max_msg_size: 2_000_000
           ]

    assert Runner.stack_opts([%{text: "Date.shift/2 -> return"}]) == []
  end
end
