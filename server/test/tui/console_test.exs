defmodule Server.Tui.ConsoleTest do
  @moduledoc """
  The console tab of the session screen. The live test runs code on
  `target@127.0.0.1` (cookie `rbtest`), as `console_root_test.exs` does:

      elixir --name rbe2e@127.0.0.1 --cookie rbtest -S mix test
  """
  # The app reads and writes the shared Server.Config, as the store tests do.
  use ExUnit.Case, async: false

  alias Server.Config

  setup do
    for n <- Config.nodes(), do: Config.delete_node(n.id)
    for s <- Config.snippets(), do: Config.delete_snippet(s.id)

    machine =
      Terra.Test.start(Server.Tui.App, app: [width: 120, height: 30], width: 120, height: 30)

    on_exit(fn -> if Process.alive?(machine), do: Terra.Test.stop(machine) end)
    %{machine: machine}
  end

  defp eventually(fun, tries \\ 750) do
    if fun.() do
      :ok
    else
      if tries == 0, do: flunk("condition never held")
      Process.sleep(20)
      eventually(fun, tries - 1)
    end
  end

  defp screen(machine), do: Terra.Test.render(machine)
  defp keys(machine, keys), do: Terra.Test.send_keys(machine, keys)
  defp history(machine), do: Terra.Test.state(machine).session.console.history

  defp open_console(machine, node_name) do
    {:ok, node_id} = Config.add_node(%{name: node_name, cookie: "rbtest"})
    {:ok, _} = Config.add_session(node_id, %{name: "con"})
    eventually(fn -> screen(machine) =~ node_name end)
    keys(machine, [:enter, :enter])
    eventually(fn -> screen(machine) =~ "▸ con" end)
    keys(machine, "]")
    eventually(fn -> screen(machine) =~ "No executions yet · n to run" end)
  end

  test "the console tab picks a snippet, shows line breaks, and has its help", %{machine: m} do
    {:ok, _} = Config.add_snippet(%{name: "two lines", code: "a = 1\na + 1"})
    open_console(m, "ghost@127.0.0.1")
    assert screen(m) =~ "[/] tabs"

    keys(m, "n")
    assert screen(m) =~ "New execution — start from"
    assert screen(m) =~ "(blank)"
    keys(m, [:down, :enter])
    assert screen(m) =~ "a = 1⏎a + 1"
    keys(m, :esc)

    keys(m, "?")
    assert screen(m) =~ "force-stop running execution"
    keys(m, "x")
    keys(m, "[")
    assert screen(m) =~ "No events yet"
    # the tab keeps its state
    keys(m, "]")
    assert screen(m) =~ "No executions yet"
  end

  test "the console runs code on the target node, saves, reruns, deletes, and clears",
       %{machine: m} do
    open_console(m, "target@127.0.0.1")

    keys(m, ["n", :enter, "1 + 2", :enter])
    eventually(fn -> match?([%{status: "ok", result: "3"}], history(m)) end)
    assert screen(m) =~ "✓"
    assert screen(m) =~ "Result"

    keys(m, ["s", "three", :enter])
    eventually(fn -> Enum.map(Config.snippets(), &{&1.name, &1.code}) == [{"three", "1 + 2"}] end)

    keys(m, "r")
    eventually(fn -> length(history(m)) == 2 end)

    keys(m, ["d", "y"])
    eventually(fn -> length(history(m)) == 1 end)

    keys(m, [{:ctrl, :l}])
    assert screen(m) =~ "Clear the entire execution history?"
    keys(m, "y")
    eventually(fn -> history(m) == [] end)
  end
end
