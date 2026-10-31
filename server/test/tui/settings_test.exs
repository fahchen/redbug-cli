defmodule Server.Tui.SettingsTest do
  @moduledoc "The settings screen of the Terra TUI (`Server.Tui.Settings`)."
  # The app reads and writes the shared Server.Config, as the other tests do.
  use ExUnit.Case, async: false

  alias Server.Config

  @defaults %{
    columns: %{name: true, pid: true, mfa: true, info: true},
    default_sort: "ts_desc",
    default_limits: %{keep: 500, time: 900, msgs: 10_000},
    theme: "tokyo-night",
    show_hints: true,
    console_timeout: 15_000
  }

  setup do
    for n <- Config.nodes(), do: Config.delete_node(n.id)
    for p <- Config.presets(), do: Config.delete_preset(p.id)
    for s <- Config.snippets(), do: Config.delete_snippet(s.id)
    # Config is shared: each test puts the default settings back.
    Config.update_settings(@defaults)
    on_exit(fn -> Config.update_settings(@defaults) end)

    machine =
      Terra.Test.start(Server.Tui.App, app: [width: 120, height: 30], width: 120, height: 30)

    on_exit(fn -> if Process.alive?(machine), do: Terra.Test.stop(machine) end)
    %{machine: machine}
  end

  defp screen(machine), do: Terra.Test.render(machine)
  defp keys(machine, keys), do: Terra.Test.send_keys(machine, keys)
  defp page(machine), do: Terra.Test.state(machine).page
  defp screen_state(machine), do: elem(page(machine), 2)

  defp open(machine) do
    keys(machine, ",")
    assert {:screen, Server.Tui.Settings, _, :nodes} = page(machine)
  end

  test ", opens the screen, esc goes back to the node screen", %{machine: m} do
    open(m)
    assert screen(m) =~ "Settings"
    assert screen(m) =~ "tokyo-night (only tokyo-night colors)"
    assert screen(m) =~ "keep 500 · time 900s · msgs 10000"
    assert screen(m) =~ "Console timeout 15s"

    keys(m, ["x", ","])
    assert {:screen, Server.Tui.Settings, %{page: :main}, :nodes} = page(m)

    keys(m, :esc)
    assert page(m) == :nodes
  end

  test "j/k move and stop at the ends", %{machine: m} do
    open(m)
    keys(m, "k")
    assert %{sel: 0} = screen_state(m)
    keys(m, List.duplicate("j", 12))
    assert %{sel: 8} = screen_state(m)
    keys(m, [:up, :down, :up])
    assert %{sel: 7} = screen_state(m)
  end

  test "space, enter, right, and l cycle the theme and the sort", %{machine: m} do
    open(m)
    keys(m, " ")
    assert Config.settings().theme == "tokyo-storm"
    keys(m, [:enter, :right, "l"])
    assert Config.settings().theme == "catppuccin-mocha"

    Config.update_settings(%{theme: "monokai"})
    keys(m, " ")
    assert Config.settings().theme == "pico-8"

    Config.update_settings(%{theme: "unknown"})
    keys(m, " ")
    assert Config.settings().theme == "pico-8"

    keys(m, ["j", " "])
    assert Config.settings().default_sort == "ts_asc"
    Config.update_settings(%{default_sort: "mfa_asc"})
    keys(m, " ")
    assert Config.settings().default_sort == "ts_desc"
  end

  test "the column rows and show hints toggle", %{machine: m} do
    open(m)
    keys(m, ["j", "j", " ", "j", " ", "j", " ", "j", " "])
    assert Config.settings().columns == %{name: false, pid: false, mfa: false, info: false}
    assert screen(m) =~ "Col · info      [ ]"
    keys(m, " ")
    assert Config.settings().columns.info

    keys(m, ["j", "j", " "])
    refute Config.settings().show_hints
    keys(m, " ")
    assert Config.settings().show_hints
  end

  test "the limits input saves good limits and keeps them on a bad text", %{machine: m} do
    open(m)
    keys(m, List.duplicate("j", 6) ++ [:enter])
    assert screen(m) =~ "Default limits — keep time msgs"
    assert screen(m) =~ "500 900 10000"

    keys(m, [:backspace, :backspace, :backspace, :backspace, :backspace, "7", :enter])
    assert Config.settings().default_limits == %{keep: 500, time: 900, msgs: 7}

    keys(m, [:enter, "x", :enter])
    assert Config.settings().default_limits.msgs == 7

    keys(m, [:enter, "1", :left, :right, :down, :esc])
    assert Config.settings().default_limits.msgs == 7
    assert %{page: :main} = screen_state(m)
  end

  test "the console timeout input takes seconds; blank and bad texts keep it", %{machine: m} do
    open(m)
    keys(m, List.duplicate("j", 8) ++ [" "])
    assert screen(m) =~ "Console timeout — seconds (current 15s · blank = keep)"

    keys(m, ["30s", :enter])
    assert Config.settings().console_timeout == 30_000
    assert screen(m) =~ "Console timeout 30s"

    keys(m, [" ", :enter, " ", "0", :enter, " ", "x", :enter])
    assert Config.settings().console_timeout == 30_000
  end

  test "? shows the help", %{machine: m} do
    open(m)
    keys(m, "?")
    assert screen(m) =~ "Help · settings"
    assert screen(m) =~ "toggle or cycle value"
    keys(m, "x")
    assert %{page: :main} = screen_state(m)
  end
end
