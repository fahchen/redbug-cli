defmodule Server.Tui.PresetsTest do
  @moduledoc "The presets screen of the Terra TUI (`Server.Tui.Presets`)."
  # The app reads and writes the shared Server.Config, as the other tests do.
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

  defp open(machine) do
    keys(machine, "p")
    assert {:screen, Server.Tui.Presets, _, :nodes} = page(machine)
  end

  defp add_preset(name, traces \\ []) do
    {:ok, id} = Config.add_preset(%{name: name, traces: traces})
    id
  end

  defp rtp(text), do: %{id: Config.gen_id(), text: text, enabled: true}
  defp preset(id), do: Enum.find(Config.presets(), &(&1.id == id))

  test "p opens the screen, esc goes back to the node screen", %{machine: m} do
    open(m)
    assert screen(m) =~ "No presets yet · n to add"
    assert screen(m) =~ "Select a preset"
    assert screen(m) =~ "0 presets"
    assert screen(m) =~ "enter traces"

    keys(m, :esc)
    assert page(m) == :nodes
    assert screen(m) =~ "p presets"
  end

  test "keys with no preset change nothing", %{machine: m} do
    open(m)
    keys(m, [:enter, "r", "d", {:ctrl, :d}, "j", "x"])
    assert {:screen, Server.Tui.Presets, %{focus: :list, page: :main}, :nodes} = page(m)
  end

  test "n adds a preset, r renames it, and a blank name changes nothing", %{machine: m} do
    open(m)
    keys(m, ["n", "probe"])
    assert screen(m) =~ "New preset — name"
    keys(m, :enter)
    eventually(fn -> Enum.map(Config.presets(), & &1.name) == ["probe"] end)
    eventually(fn -> screen(m) =~ "probe" end)
    assert screen(m) =~ "keep"

    keys(m, ["r", :backspace, :backspace, :backspace, :backspace, :backspace, "calls", :enter])
    eventually(fn -> Enum.map(Config.presets(), & &1.name) == ["calls"] end)

    keys(m, ["n", "  ", :enter])
    keys(m, ["n", "x", :left, :right, :down, :esc])
    assert length(Config.presets()) == 1
    assert {:screen, _, %{page: :main}, _} = page(m)
  end

  test "j/k move and wrap, d asks, n keeps, y deletes, ctrl+d deletes", %{machine: m} do
    a = add_preset("alpha")
    b = add_preset("beta")
    c = add_preset("gamma")
    open(m)

    keys(m, "k")
    assert {:screen, _, %{sel: 2}, _} = page(m)
    keys(m, [:down, :up, "j", "x"])
    assert {:screen, _, %{sel: 0, page: :main}, _} = page(m)
    keys(m, "j")

    keys(m, "d")
    assert screen(m) =~ ~s(Delete preset "beta"?)
    keys(m, ["x", "n"])
    assert preset(b)
    keys(m, ["d", :esc])
    assert preset(b)

    keys(m, ["d", "y"])
    eventually(fn -> preset(b) == nil end)
    assert {:screen, _, %{sel: 0}, _} = page(m)

    keys(m, {:ctrl, :d})
    eventually(fn -> preset(a) == nil end)
    assert preset(c)
  end

  test "the traces panel adds, edits, deletes patterns and sets the limits", %{machine: m} do
    id = add_preset("probe")
    open(m)
    assert screen(m) =~ "No patterns yet"

    keys(m, :tab)
    assert {:screen, _, %{focus: :detail}, _} = page(m)
    assert screen(m) =~ "tab/esc back"
    keys(m, ["j", "e", "d", {:ctrl, :d}, "x"])

    keys(m, "n")
    assert screen(m) =~ "New RTP"
    assert screen(m) =~ "Common RTP rules (Elixir)"
    keys(m, ["lists:seq/2", :enter])
    eventually(fn -> Enum.map(preset(id).traces, & &1.text) == ["lists:seq/2"] end)
    keys(m, ["n", " ", :enter])
    assert length(preset(id).traces) == 1

    keys(m, ["e", " -> return"])
    assert screen(m) =~ "Edit RTP"
    keys(m, :enter)
    eventually(fn -> Enum.map(preset(id).traces, & &1.text) == ["lists:seq/2 -> return"] end)
    eventually(fn -> screen(m) =~ "lists:seq/2 -> return" end)

    keys(m, "l")
    assert screen(m) =~ "Limits — keep time msgs"
    keys(m, [:backspace, :backspace, :backspace, :backspace, :backspace, "10", :enter])
    eventually(fn -> preset(id).limits == %{keep: 500, time: 900, msgs: 10} end)
    keys(m, ["l", "x", :enter])
    assert preset(id).limits.msgs == 10

    keys(m, ["d"])
    assert screen(m) =~ "Delete this pattern?"
    keys(m, "y")
    eventually(fn -> preset(id).traces == [] end)

    keys(m, :esc)
    assert {:screen, _, %{focus: :list}, _} = page(m)
  end

  test "j/k wrap in the traces, and ctrl+d deletes a pattern", %{machine: m} do
    id = add_preset("probe", [rtp("one:a/1"), rtp("two:b/2")])
    open(m)
    keys(m, [:enter, "k"])
    assert {:screen, _, %{trace_sel: 1}, _} = page(m)
    keys(m, [:down, :up, "j"])
    assert {:screen, _, %{trace_sel: 0}, _} = page(m)

    keys(m, {:ctrl, :d})
    eventually(fn -> Enum.map(preset(id).traces, & &1.text) == ["two:b/2"] end)
    keys(m, "x")
    assert {:screen, _, %{page: :main, focus: :detail}, _} = page(m)

    keys(m, ["e", :esc])
    assert {:screen, _, %{page: :main, focus: :detail}, _} = page(m)
  end

  test "the traces focus goes back to the list when the preset goes", %{machine: m} do
    id = add_preset("probe")
    open(m)
    keys(m, :enter)
    Config.delete_preset(id)
    eventually(fn -> screen(m) =~ "No presets yet" end)
    keys(m, "j")
    assert {:screen, _, %{focus: :list}, _} = page(m)
  end

  test "a pattern of a preset that goes while the input is open changes nothing",
       %{machine: m} do
    id = add_preset("probe")
    open(m)
    keys(m, [:enter, "n", "lists:seq/2"])
    Config.delete_preset(id)
    keys(m, :enter)
    assert Config.presets() == []
  end

  test "? shows the help, and , opens the settings", %{machine: m} do
    open(m)
    keys(m, "?")
    assert screen(m) =~ "Help · presets"
    assert screen(m) =~ "focus traces"
    keys(m, "x")
    assert {:screen, Server.Tui.Presets, %{page: :main}, _} = page(m)

    keys(m, ",")
    assert {:screen, Server.Tui.Settings, _, {:screen, Server.Tui.Presets, _, :nodes}} = page(m)
    keys(m, :esc)
    assert {:screen, Server.Tui.Presets, _, :nodes} = page(m)
  end

  test "the hints follow the show_hints setting", %{machine: m} do
    on_exit(fn -> Config.update_settings(%{show_hints: true}) end)
    open(m)
    Config.update_settings(%{show_hints: false})
    eventually(fn -> not (screen(m) =~ "enter traces") end)
  end
end
