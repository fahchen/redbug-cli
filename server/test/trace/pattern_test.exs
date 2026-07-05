defmodule Server.Trace.PatternTest do
  use ExUnit.Case, async: true

  alias Server.Trace.Pattern

  describe "to_redbug/1" do
    test "rewrites Elixir module + function to quoted Erlang atom + colon" do
      assert Pattern.to_redbug("Demo.add/2 -> return") == "'Elixir.Demo':add/2 -> return"
    end

    test "handles nested module paths, keeping the function separator" do
      assert Pattern.to_redbug("MyApp.Worker.handle/2") == "'Elixir.MyApp.Worker':handle/2"
    end

    test "module-only pattern" do
      assert Pattern.to_redbug("Demo") == "'Elixir.Demo'"
    end

    test "module + function without arity" do
      assert Pattern.to_redbug("Demo.add") == "'Elixir.Demo':add"
    end

    test "drops a dangling separator dot (no function)" do
      assert Pattern.to_redbug("Demo.") == "'Elixir.Demo'"
    end

    test "leaves args, guards and actions untouched" do
      assert Pattern.to_redbug("Demo.add(1, X) -> return") == "'Elixir.Demo':add(1, X) -> return"
    end

    test "leaves return stack actions untouched" do
      assert Pattern.to_redbug("Date.shift/2 -> return;stack") ==
               "'Elixir.Date':shift/2 -> return;stack"
    end

    test "translates Elixir erlang-module notation to Erlang form" do
      assert Pattern.to_redbug(":lists.reverse/1") == "lists:reverse/1"
    end

    test "passes through native Erlang form unchanged" do
      assert Pattern.to_redbug("lists:reverse/1") == "lists:reverse/1"
    end

    test "passes through already-quoted Erlang form unchanged" do
      assert Pattern.to_redbug("'Elixir.Demo':add/2 -> return") ==
               "'Elixir.Demo':add/2 -> return"
    end

    test "translated Elixir patterns compile under redbug" do
      for {input, mfa} <- [
            {"Demo.add/2 -> return", {Demo, :add, 2}},
            {"Demo", {Demo, :_, :_}},
            {":lists.reverse/1", {:lists, :reverse, 1}}
          ] do
        compiled =
          input
          |> Pattern.to_redbug()
          |> String.to_charlist()
          |> :redbug_compiler.compile()

        assert elem(compiled, 0) == mfa
      end
    end
  end
end
