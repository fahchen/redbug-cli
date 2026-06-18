defmodule Server.EpmdTest do
  # connect-only epmd shim: address_please must resolve name@host → pinned
  # endpoint, or distribution silently fails to dial the target.
  use ExUnit.Case, async: false

  # The app (test_helper) starts Server.Config, which owns the named
  # `:redbug_endpoints` table; insert/clean our own key against it.
  setup do
    on_exit(fn -> :ets.delete(:redbug_endpoints, :"app@prod-1") end)
    :ok
  end

  test "resolves a known node to its endpoint with the dist proto version" do
    :ets.insert(:redbug_endpoints, {:"app@prod-1", {{127, 0, 0, 1}, 9100}})

    assert Server.Epmd.address_please(~c"app", ~c"prod-1", :inet) ==
             {:ok, {127, 0, 0, 1}, 9100, 5}
  end

  test "unknown node is nxdomain (so connect fails cleanly, not a crash)" do
    assert Server.Epmd.address_please(~c"ghost", ~c"prod-1", :inet) == {:error, :nxdomain}
  end

  test "register_node is a no-op returning a fake creation" do
    assert {:ok, creation} = Server.Epmd.register_node(~c"controller", 0)
    assert creation in 1..3
  end
end
