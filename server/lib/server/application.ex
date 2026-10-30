defmodule Server.Application do
  @moduledoc false

  use Application

  @impl Application
  def start(_type, _args) do
    if Server.Dist.enabled?(), do: ensure_distributed()

    children = [
      Server.PubSub,
      Server.Config,
      # after Config: SshTunnel writes the :redbug_endpoints table Config owns.
      Server.SshTunnel,
      {Registry, keys: :unique, name: Server.Trace.Registry},
      {DynamicSupervisor, strategy: :one_for_one, name: Server.Trace.Supervisor},
      {Registry, keys: :unique, name: Server.Remote.Registry},
      {DynamicSupervisor, strategy: :one_for_one, name: Server.Remote.Supervisor}
    ]

    # last: the TUI reads the state of the children above.
    children = if Server.Tui.enabled?(), do: children ++ [Server.Tui], else: children

    Supervisor.start_link(children, strategy: :one_for_one, name: Server.Supervisor)
  end

  # redbug remote tracing needs the controller node to be alive and distributed
  # so it can connect to the target node with a matching cookie.
  #
  # A node is either a longname or a shortname node for its whole life, and Erlang
  # refuses to connect the two — so to trace a shortname target (an Elixir release
  # left on its `-sname` default, e.g. Kamal's `muku@178`), boot the controller as
  # shortnames too via `CONTROLLER_DISTRIBUTION=sname`. Default is longnames.
  #
  # The controller joins as a HIDDEN node with connect_all disabled: the target is
  # usually a node in a production cluster, and a visible node would (a) make
  # `global` fan out a full mesh to every peer it discovers (unreachable through
  # our single tunnel) and then disconnect the target to "prevent overlapping
  # partitions", and (b) pull the controller into that cluster. Hidden + no
  # connect_all keeps us to exactly the one node we dial; redbug still traces.
  defp ensure_distributed do
    Application.put_env(:kernel, :connect_all, false)

    unless Node.alive?() do
      {name, domain} = controller_identity()
      {:ok, _} = :net_kernel.start(name, %{name_domain: domain, hidden: true})
    end

    if cookie = System.get_env("CONTROLLER_COOKIE") do
      Node.set_cookie(String.to_atom(cookie))
    end
  end

  defp controller_identity do
    node = System.get_env("CONTROLLER_NODE", "redbug_controller@127.0.0.1")

    case System.get_env("CONTROLLER_DISTRIBUTION") do
      "sname" ->
        # shortnames can't carry a dotted `@host`; take the bare name and let the
        # VM append the short host.
        {node |> String.split("@") |> hd() |> String.to_atom(), :shortnames}

      _ ->
        {String.to_atom(node), :longnames}
    end
  end
end
