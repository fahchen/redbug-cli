defmodule Server.Epmd do
  @moduledoc """
  Connect-only epmd replacement, installed via the VM flags
  `-start_epmd false -epmd_module Elixir.Server.Epmd` when `REDBUG_NODES` is set.

  The controller never registers in any real epmd and never queries one: outbound
  `Node.connect/1` resolves a target's dial endpoint straight from the
  `:redbug_endpoints` ETS table (`Server.Config` fills it from `REDBUG_NODES`),
  so distribution skips DNS + epmd entirely. This is what lets an `ssh -L` tunnel
  on `127.0.0.1:<port>` work without colliding with the controller's own epmd.

  `register_node/3` is a no-op returning a fake creation — the controller only
  makes outbound connections, nothing needs to find it by name.
  """

  @endpoints :redbug_endpoints

  # epmd_module callbacks ----------------------------------------------------

  def start_link, do: :ignore

  def register_node(name, port), do: register_node(name, port, :inet)
  def register_node(_name, _port, _family), do: {:ok, :rand.uniform(3)}

  def port_please(name, host), do: address_please(name, host, :inet)
  def port_please(name, host, _timeout), do: address_please(name, host, :inet)

  def listen_port_please(_name, _host), do: {:ok, 0}

  def names(_host), do: {:error, :address}

  @doc """
  Resolve `name@host` to its pinned `{ip, port}` from the endpoint table.
  `5` is the distribution protocol version (OTP 23+).
  """
  def address_please(name, host, _family) do
    case lookup(:"#{name}@#{host}") do
      {ip, port} -> {:ok, ip, port, 5}
      nil -> {:error, :nxdomain}
    end
  end

  defp lookup(key) do
    case :ets.whereis(@endpoints) do
      :undefined ->
        nil

      _ ->
        case :ets.lookup(@endpoints, key) do
          [{^key, endpoint}] -> endpoint
          _ -> nil
        end
    end
  end
end
