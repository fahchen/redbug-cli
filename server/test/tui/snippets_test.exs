defmodule Server.Tui.SnippetsTest do
  @moduledoc "The snippets screen of the Terra TUI (`Server.Tui.Snippets`)."
  # The app reads and writes the shared Server.Config, as the store tests do.
  use ExUnit.Case, async: false

  alias Server.Config

  setup do
    for n <- Config.nodes(), do: Config.delete_node(n.id)
    for p <- Config.presets(), do: Config.delete_preset(p.id)
    for s <- Config.snippets(), do: Config.delete_snippet(s.id)

    machine =
      Terra.Test.start(Server.Tui.App, app: [width: 120, height: 30], width: 120, height: 30)

    on_exit(fn -> if Process.alive?(machine), do: Terra.Test.stop(machine) end)
    %{machine: machine}
  end

  defp eventually(fun, tries \\ 100) do
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
  defp page(machine), do: Terra.Test.state(machine).page
  defp screen_state(machine), do: elem(page(machine), 2)

  defp open(machine) do
    keys(machine, "l")
    assert {:screen, Server.Tui.Snippets, _, :nodes} = page(machine)
  end

  defp add_snippet(name, code \\ "") do
    {:ok, id} = Config.add_snippet(%{name: name, code: code})
    id
  end

  defp snippet(id), do: Enum.find(Config.snippets(), &(&1.id == id))

  test "l opens the screen, esc goes back to the node screen", %{machine: m} do
    open(m)
    assert screen(m) =~ "No snippets yet · n to add"
    assert screen(m) =~ "Select a snippet"
    assert screen(m) =~ "Snippets (0)"
    assert screen(m) =~ "#g jump"

    keys(m, ["j", "e", "r", "f", "d", {:ctrl, :d}, {:ctrl, :f}, {:ctrl, :b}, "1", "g"])
    assert %{page: :main, sel: 0, digits: ""} = screen_state(m)

    keys(m, :esc)
    assert page(m) == :nodes
  end

  test "n creates a snippet and opens its code input, enter saves formatted code",
       %{machine: m} do
    open(m)
    keys(m, ["n", "  ", :enter])
    assert Config.snippets() == []

    keys(m, ["n", "double"])
    assert screen(m) =~ "New snippet — name"
    keys(m, :enter)
    eventually(fn -> Enum.map(Config.snippets(), & &1.name) == ["double"] end)
    assert screen(m) =~ "Edit code"
    assert screen(m) =~ "↵ marks a line break"

    keys(m, ["a=1;b=2", :enter])
    [s] = Config.snippets()
    assert s.code == "a = 1\nb = 2"
    eventually(fn -> screen(m) =~ "a = 1" end)
    assert screen(m) =~ " 1 · double"
  end

  test "e edits a multi-line snippet with ↵ marks, esc cancels", %{machine: m} do
    id = add_snippet("two", "x = 1\ny = 2")
    open(m)
    keys(m, "e")
    assert screen(m) =~ "x = 1↵y = 2"
    keys(m, [:backspace, "3", :enter])
    eventually(fn -> snippet(id).code == "x = 1\ny = 3" end)

    keys(m, ["e", "z", :left, :right, :up, :esc])
    assert snippet(id).code == "x = 1\ny = 3"
    assert %{page: :main} = screen_state(m)
  end

  test "r renames, f formats, and a blank name changes nothing", %{machine: m} do
    id = add_snippet("one", "a=1")
    open(m)
    assert screen(m) =~ "a=1"

    keys(m, ["r", :backspace, :backspace, :backspace, "uno", :enter])
    eventually(fn -> snippet(id).name == "uno" end)
    keys(m, ["r", :backspace, :backspace, :backspace, :enter])
    assert snippet(id).name == "uno"

    keys(m, "f")
    eventually(fn -> snippet(id).code == "a = 1" end)
  end

  test "an empty snippet says so", %{machine: m} do
    add_snippet("blank")
    open(m)
    assert screen(m) =~ "Empty · e to edit"
  end

  test "a blank line of the code stays blank", %{machine: m} do
    add_snippet("gap", ":first\n\n:third")
    open(m)
    assert screen(m) =~ ~r/:first *│\n│ *│ *│\n│ *│ :third/
  end

  test "j/k wrap, #g jumps, and a digit run clears on another key", %{machine: m} do
    for name <- ~w(alpha beta gamma), do: add_snippet(name, ":#{name}")
    open(m)

    keys(m, "k")
    assert %{sel: 2} = screen_state(m)
    eventually(fn -> screen(m) =~ ":gamma" end)
    keys(m, [:down, :up, "j"])
    assert %{sel: 0} = screen_state(m)

    keys(m, ["2", "g"])
    assert %{sel: 1, digits: ""} = screen_state(m)
    keys(m, ["9", "g"])
    assert %{sel: 2} = screen_state(m)
    keys(m, ["0", "g"])
    assert %{sel: 2} = screen_state(m)
    keys(m, ["1", "x", "g"])
    assert %{sel: 2, digits: ""} = screen_state(m)
  end

  test "d asks, n and esc keep, y deletes, ctrl+d deletes", %{machine: m} do
    a = add_snippet("alpha")
    b = add_snippet("beta")
    c = add_snippet("gamma")
    open(m)
    keys(m, "j")

    keys(m, "d")
    assert screen(m) =~ ~s(Delete snippet "beta"?)
    keys(m, ["x", "n", "d", :esc])
    assert snippet(b)

    keys(m, ["d", "y"])
    eventually(fn -> snippet(b) == nil end)
    assert %{sel: 0} = screen_state(m)

    keys(m, {:ctrl, :d})
    eventually(fn -> snippet(a) == nil end)
    assert snippet(c)
  end

  test "ctrl+f and ctrl+b scroll the code by a page", %{machine: m} do
    code = Enum.map_join(1..60, "\n", &":line#{&1}")
    add_snippet("long", code)
    open(m)
    assert screen(m) =~ ":line1\n" or screen(m) =~ ":line1 "
    refute screen(m) =~ ":line40"

    keys(m, {:ctrl, :f})
    assert screen(m) =~ ":line40"
    refute screen(m) =~ ":line1 "

    keys(m, List.duplicate({:ctrl, :f}, 100))
    assert %{code_page: 59} = screen_state(m)
    assert screen(m) =~ ":line60"

    keys(m, List.duplicate({:ctrl, :b}, 100))
    assert %{code_page: 0} = screen_state(m)
    assert screen(m) =~ ":line2 "
  end

  test "? shows the help, and , opens the settings", %{machine: m} do
    open(m)
    keys(m, "?")
    assert screen(m) =~ "Help · snippets"
    keys(m, "x")
    assert %{page: :main} = screen_state(m)

    keys(m, ",")
    assert {:screen, Server.Tui.Settings, _, {:screen, Server.Tui.Snippets, _, :nodes}} = page(m)
    keys(m, :esc)
    assert {:screen, Server.Tui.Snippets, _, :nodes} = page(m)
  end

  test "the hints follow the show_hints setting", %{machine: m} do
    on_exit(fn -> Config.update_settings(%{show_hints: true}) end)
    open(m)
    Config.update_settings(%{show_hints: false})
    eventually(fn -> not (screen(m) =~ "#g jump") end)
  end
end
