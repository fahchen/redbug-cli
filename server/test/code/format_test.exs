defmodule Server.Code.FormatTest do
  use ExUnit.Case, async: true

  alias Server.Code.Format

  describe "run/1" do
    test "formats Elixir source" do
      assert Format.run("def f(  x ),do: x+1") == "def f(x), do: x + 1"
    end

    test "formats an Erlang expression sequence" do
      assert Format.run("lists:seq(1,5).") == "lists:seq(1, 5)"
    end

    test "leaves unparseable input untouched" do
      garbage = "<<<not code>>>"
      assert Format.run(garbage) == garbage
    end

    test "passes already-formatted Elixir through unchanged" do
      assert Format.run("x = 1\n") == "x = 1"
    end
  end
end
