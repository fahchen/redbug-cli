defmodule Server.Application do
  @moduledoc false

  use Application

  @impl Application
  def start(_type, _args) do
    ensure_distributed()

    children = [
      {Phoenix.PubSub, name: Server.PubSub},
      Server.Config,
      {Registry, keys: :unique, name: Server.Trace.Registry},
      {DynamicSupervisor, strategy: :one_for_one, name: Server.Trace.Supervisor},
      ServerWeb.Endpoint
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Server.Supervisor)
  end

  # redbug remote tracing needs the controller node to be alive and distributed
  # so it can connect to the target node with a matching cookie.
  defp ensure_distributed do
    unless Node.alive?() do
      name = String.to_atom(System.get_env("CONTROLLER_NODE", "redbug_controller@127.0.0.1"))
      {:ok, _} = :net_kernel.start([name, :longnames])
    end

    if cookie = System.get_env("CONTROLLER_COOKIE") do
      Node.set_cookie(String.to_atom(cookie))
    end
  end
end
