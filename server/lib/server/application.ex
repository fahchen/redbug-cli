defmodule Server.Application do
  @moduledoc false

  use Application

  @impl Application
  def start(_type, _args) do
    ensure_distributed()
    configure_port()

    children = [
      {Phoenix.PubSub, name: Server.PubSub},
      Server.Config,
      # after Config: SshTunnel writes the :redbug_endpoints table Config owns.
      Server.SshTunnel,
      {Registry, keys: :unique, name: Server.Trace.Registry},
      {DynamicSupervisor, strategy: :one_for_one, name: Server.Trace.Supervisor},
      {Registry, keys: :unique, name: Server.Remote.Registry},
      {DynamicSupervisor, strategy: :one_for_one, name: Server.Remote.Supervisor},
      ServerWeb.Endpoint
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Server.Supervisor)
  end

  # redbug remote tracing needs the controller node to be alive and distributed
  # so it can connect to the target node with a matching cookie.
  #
  # A node is either a longname or a shortname node for its whole life, and Erlang
  # refuses to connect the two — so to trace a shortname target (an Elixir release
  # left on its `-sname` default, e.g. Kamal's `muku@178`), boot the controller as
  # shortnames too via `CONTROLLER_DISTRIBUTION=sname`. Default is longnames.
  defp ensure_distributed do
    unless Node.alive?() do
      {name, mode} = controller_identity()
      {:ok, _} = :net_kernel.start([name, mode])
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

  # The WS port is dynamic so multiple instances never collide: REDBUG_PORT pins
  # it (launcher-driven), otherwise the OS hands us a free port via listen(0).
  # We write the chosen port to REDBUG_PORT_FILE so the TUI can discover it.
  defp configure_port do
    port = resolve_port()
    config = Application.get_env(:server, ServerWeb.Endpoint, [])
    http = config |> Keyword.get(:http, []) |> Keyword.put(:port, port)
    Application.put_env(:server, ServerWeb.Endpoint, Keyword.put(config, :http, http))
    announce_port(port)
  end

  defp resolve_port do
    case System.get_env("REDBUG_PORT") do
      p when is_binary(p) and p != "" -> String.to_integer(p)
      _ -> free_port()
    end
  end

  defp free_port do
    {:ok, socket} = :gen_tcp.listen(0, ip: {127, 0, 0, 1})
    {:ok, port} = :inet.port(socket)
    :gen_tcp.close(socket)
    port
  end

  defp announce_port(port) do
    if file = System.get_env("REDBUG_PORT_FILE") do
      File.mkdir_p!(Path.dirname(file))
      File.write!(file, Integer.to_string(port))
    end

    IO.puts("redbug ws port: #{port}")
  end
end
