defmodule Server.DistSwitchTest do
  # The switch acts at application start, so each case boots the app in a new
  # VM with its own REDBUG_DIST and config file; this VM keeps its own setting.
  use ExUnit.Case, async: true

  @moduletag timeout: 120_000

  # Runs in the child VM: start the app, add one node, connect to it, and print
  # the result as the last stdout line.
  @child_script """
  Application.put_all_env(Config.Reader.read!("config/config.exs", env: :test))
  Application.put_env(:server, :config_path, System.fetch_env!("RB_TEST_CONFIG"))
  {:ok, _} = Application.ensure_all_started(:server)
  Server.Config.add_node(%{name: System.fetch_env!("RB_TEST_TARGET"), cookie: System.fetch_env!("RB_TEST_COOKIE")})
  [node] = Server.Config.nodes()
  result = {Node.alive?(), Process.whereis(:net_kernel) != nil, Server.Config.connect_node(node.id)}
  IO.puts(result |> :erlang.term_to_binary() |> Base.encode64())
  """

  test "REDBUG_DIST=off boots without distribution, and connect fails with :distribution_off" do
    assert {false, false, {:error, :distribution_off}} =
             boot(%{"REDBUG_DIST" => "off"}, "nobody@127.0.0.1", "c")
  end

  test "without REDBUG_DIST, the app starts distribution and connects to a node" do
    # The child connects to this VM, which the app (or `elixir --name`) made distributed.
    assert Node.alive?()
    cookie = Atom.to_string(Node.get_cookie())
    name = "rb_dist_on_#{System.unique_integer([:positive])}@127.0.0.1"
    env = %{"REDBUG_DIST" => nil, "CONTROLLER_NODE" => name, "CONTROLLER_COOKIE" => cookie}

    assert {true, true, :ok} = boot(env, Atom.to_string(Node.self()), cookie)
  end

  defp boot(env, target, cookie) do
    config =
      Path.join(System.tmp_dir!(), "redbug_dist_test_#{System.unique_integer([:positive])}.json")

    on_exit(fn -> File.rm(config) end)

    paths =
      [
        Mix.Project.consolidation_path()
        | Path.wildcard(Path.join(Mix.Project.build_path(), "lib/*/ebin"))
      ]
      |> Enum.flat_map(&["-pa", &1])

    env =
      Map.merge(env, %{
        "RB_TEST_CONFIG" => config,
        "RB_TEST_TARGET" => target,
        "RB_TEST_COOKIE" => cookie
      })

    {out, 0} =
      System.cmd(System.find_executable("elixir"), paths ++ ["-e", @child_script],
        env: Enum.to_list(env),
        stderr_to_stdout: true
      )

    out
    |> String.split("\n", trim: true)
    |> List.last()
    |> Base.decode64!()
    |> :erlang.binary_to_term()
  end
end
