defmodule Server.Tui.AppTest do
  # The app reads and writes the shared Server.Config, as the store tests do.
  use ExUnit.Case, async: false

  alias Server.Config

  setup do
    for n <- Config.nodes(), do: Config.delete_node(n.id)

    machine =
      Terra.Test.start(Server.Tui.App, app: [width: 100, height: 30], width: 100, height: 30)

    on_exit(fn -> if Process.alive?(machine), do: Terra.Test.stop(machine) end)
    %{machine: machine}
  end

  # Config changes reach the app through the bridge; wait until `fun` holds.
  defp eventually(fun, tries \\ 50) do
    if fun.() do
      :ok
    else
      if tries == 0, do: flunk("condition never held")
      Process.sleep(20)
      eventually(fun, tries - 1)
    end
  end

  defp screen(machine), do: Terra.Test.render(machine)

  defp add_node(machine, name, cookie) do
    {:ok, id} = Config.add_node(%{name: name, cookie: cookie})
    eventually(fn -> screen(machine) =~ name end)
    id
  end

  test "an empty list shows the first-node hint and the status line", %{machine: m} do
    assert screen(m) =~ "No nodes yet"
    assert screen(m) =~ "0/0 connected"
    assert screen(m) =~ "j/k node"
  end

  test "n opens the form, and Enter adds the node", %{machine: m} do
    Terra.Test.send_keys(m, "n")
    assert screen(m) =~ "New node"

    Terra.Test.send_keys(m, ["app", :tab, "127.0.0.1", :tab, "secret", :enter])

    eventually(fn -> Enum.map(Config.nodes(), & &1.name) == ["app@127.0.0.1"] end)
    eventually(fn -> screen(m) =~ "app@127.0.0.1" end)
    assert screen(m) =~ "Cookie  se••••et"
  end

  test "the form shows the validation error and keeps the page", %{machine: m} do
    Terra.Test.send_keys(m, ["n", "app", :enter])
    assert screen(m) =~ "✗ Direct node needs a name and cookie"

    Terra.Test.send_keys(m, [:tab, "12", :tab, "c", :enter])
    assert screen(m) =~ "Host must be a hostname or IP"

    Terra.Test.send_keys(m, :esc)
    assert screen(m) =~ "No nodes yet"
    assert Config.nodes() == []
  end

  test "e edits the node with its name split at @", %{machine: m} do
    id = add_node(m, "app@127.0.0.1", "secret")
    Terra.Test.send_keys(m, "e")
    assert screen(m) =~ "Edit node"

    # Shift+Tab (`{:ctrl, :tab}`) from the first field goes to the last one, Label.
    Terra.Test.send_keys(m, [{:ctrl, :tab}, "Staging", :enter])

    eventually(fn -> Config.fetch_node(id).label == "Staging" end)
    assert Config.fetch_node(id).name == "app@127.0.0.1"
    eventually(fn -> screen(m) =~ "Label  Staging" end)
  end

  test "d asks first, and y deletes the node", %{machine: m} do
    add_node(m, "app@127.0.0.1", "secret")
    Terra.Test.send_keys(m, "d")
    assert screen(m) =~ ~s(Delete node "app@127.0.0.1" and all its sessions?)

    Terra.Test.send_keys(m, "n")
    assert screen(m) =~ "app@127.0.0.1"

    Terra.Test.send_keys(m, ["d", "y"])
    eventually(fn -> Config.nodes() == [] end)
    eventually(fn -> screen(m) =~ "No nodes yet" end)
  end

  test "j/k move the selection with wrap", %{machine: m} do
    add_node(m, "a@127.0.0.1", "c")
    add_node(m, "b@127.0.0.1", "c")
    assert screen(m) =~ " a@127.0.0.1 "

    Terra.Test.send_keys(m, "j")
    assert screen(m) =~ " b@127.0.0.1 "
    assert Terra.Test.state(m).selected == 1

    Terra.Test.send_keys(m, "j")
    assert Terra.Test.state(m).selected == 0

    Terra.Test.send_keys(m, "k")
    assert Terra.Test.state(m).selected == 1
  end

  test "c connects the node and shows the result", %{machine: m} do
    id = add_node(m, "rb_tui_self@127.0.0.1", "")
    # Connect to this VM itself, which the test run makes distributed.
    Config.update_node(id, %{
      name: Atom.to_string(node()),
      cookie: Atom.to_string(Node.get_cookie())
    })

    eventually(fn -> screen(m) =~ Atom.to_string(node()) end)

    Terra.Test.send_keys(m, "c")
    eventually(fn -> screen(m) =~ "1/1 connected" end)
    assert screen(m) =~ "●"

    Terra.Test.send_keys(m, "c")
    eventually(fn -> screen(m) =~ "0/1 connected" end)
  end

  test "the layout follows the resize event", %{machine: m} do
    Terra.Test.resize(m, 60, 12)
    assert %{width: 60, height: 12} = Terra.Test.state(m)
    lines = m |> screen() |> String.split("\n")
    assert List.last(lines) =~ "0/0 connected"
    # the bottom border of the panels is on the row above the status line
    assert Enum.at(lines, -2) =~ "└"
  end

  test "a wide label fits the list row", %{machine: m} do
    {:ok, _} =
      Config.add_node(%{name: "w@127.0.0.1", cookie: "c", label: String.duplicate("节", 30)})

    eventually(fn -> screen(m) =~ "节" end)
    row = m |> screen() |> String.split("\n") |> Enum.find(&(&1 =~ "节"))
    # the session count stays in the row, and the label ends with the cut mark
    assert row =~ "… 0"
  end

  test "? shows the help, and q asks before it quits", %{machine: m} do
    Terra.Test.send_keys(m, "?")
    assert screen(m) =~ "press any key to close"
    Terra.Test.send_keys(m, "x")
    assert screen(m) =~ "No nodes yet"

    Terra.Test.send_keys(m, "q")
    assert screen(m) =~ "Quit redbug?"
    ref = Process.monitor(m)
    Terra.Test.send_keys(m, "y")
    assert_receive {:DOWN, ^ref, :process, ^m, :normal}
  end
end
