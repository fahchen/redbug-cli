defmodule Server.Stores.ChildStoresSmokeTest do
  use ExUnit.Case, async: false

  alias Musubi.Testing
  alias Server.Config

  setup do
    for n <- Config.nodes(), do: Config.delete_node(n.id)
    for p <- Config.presets(), do: Config.delete_preset(p.id)
    :ok
  end

  # Config mutations broadcast {:config_updated} async; the root re-renders and
  # (re)mounts children on receipt. Settle before asserting the new tree.
  defp settle, do: Process.sleep(50)

  defp dispatch(page, name, payload, path \\ []) do
    Testing.dispatch_command(page, name, payload, path)
    settle()
  end

  test "node tree: root create + node/session child commands" do
    page = Testing.mount(Server.Stores.NodesRoot)

    dispatch(page, :createNode, %{name: "n1@host", cookie: "c", label: "prod"})
    # root render returns %Musubi.Child{} entries; only id is exposed here, the
    # resolved fields live behind the child store path
    assert [node] = Testing.render(page).nodes
    nid = node.id

    # store_id path embeds the field-name segment: nodes/<id>, nodes/<id>/sessions/<id>
    node_path = ["nodes", nid]
    assert Testing.render(page, node_path).name == "n1@host"
    # label must survive create; it rides through every node layer (createNode →
    # Config.add_node → NodeStore.render), a path that silently dropped it before.
    assert Testing.render(page, node_path).label == "prod"
    assert Testing.render(page, node_path).sessions == []

    # editNode on the node child — no id in payload
    dispatch(page, :editNode, %{name: "renamed", label: "staging"}, node_path)
    assert Testing.render(page, node_path).name == "renamed"
    assert Testing.render(page, node_path).label == "staging"

    # createSession on the node child
    dispatch(page, :createSession, %{name: "s1", from_preset_id: nil}, node_path)
    assert [session] = Testing.render(page, node_path).sessions
    sid = session.id
    session_path = ["nodes", nid, "sessions", sid]
    assert Testing.render(page, session_path).name == "s1"

    # deleteSession on the session grandchild — empty payload
    dispatch(page, :deleteSession, %{}, session_path)
    assert Testing.render(page, node_path).sessions == []

    # deleteNode on the node child
    dispatch(page, :deleteNode, %{}, node_path)
    assert Testing.render(page).nodes == []
  end

  test "presets: root create + preset child commands" do
    page = Testing.mount(Server.Stores.PresetsRoot)

    dispatch(page, :createPreset, %{name: "p1"})
    assert [preset] = Testing.render(page).presets
    pid = preset.id

    # store_id path embeds the field-name segment: presets/<id>
    preset_path = ["presets", pid]

    dispatch(page, :addPresetTrace, %{text: "lists:seq/2"}, preset_path)
    assert [rtp] = Testing.render(page, preset_path).traces
    assert rtp.text == "lists:seq/2"
    assert rtp.enabled == true

    dispatch(page, :togglePresetTrace, %{trace_id: rtp.id}, preset_path)
    assert [%{enabled: false}] = Testing.render(page, preset_path).traces

    dispatch(page, :updatePresetLimits, %{keep: 1, time: 2, msgs: 3}, preset_path)
    assert Testing.render(page, preset_path).limits == %{keep: 1, time: 2, msgs: 3}

    dispatch(page, :deletePresetTrace, %{trace_id: rtp.id}, preset_path)
    assert Testing.render(page, preset_path).traces == []

    dispatch(page, :deletePreset, %{}, preset_path)
    assert Testing.render(page).presets == []
  end
end
