defmodule Server.Trace.RunnerTest do
  use ExUnit.Case, async: true

  alias Server.Trace.Runner

  test "stack traces raise redbug max message size" do
    assert Runner.stack_opts([%{text: "Date.shift/2 -> return;stack"}]) == [
             max_msg_size: 2_000_000
           ]

    assert Runner.stack_opts([%{text: "Date.shift/2 -> return"}]) == []
  end
end
