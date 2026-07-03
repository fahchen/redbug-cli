defmodule Server.Epmd do
  @moduledoc """
  Connect-only epmd replacement, installed via the VM flags
  `-start_epmd false -epmd_module Elixir.Server.Epmd`.

  Always installed (not just for `REDBUG_NODES`): outbound `Node.connect/1` first
  checks the `:redbug_endpoints` ETS table (filled by `Server.Config` from
  `REDBUG_NODES` and by `Server.SshTunnel`) for a pinned `{ip, port}` dial target.
  A pinned name skips DNS + epmd entirely, which is what lets an `ssh -L` tunnel
  on `127.0.0.1:<port>` work without colliding with the controller's own epmd.
  An **unpinned** name falls back to the real `:erl_epmd`, so plain routable
  nodes still resolve through their host's epmd as usual.

  The controller never registers in any real epmd (`register_node/3` is a no-op
  returning a fake creation) — it only makes outbound connections, nothing needs
  to find it by name.
  """

  @endpoints :redbug_endpoints

  # epmd_module callbacks ----------------------------------------------------

  def start_link, do: :ignore

  def register_node(name, port), do: register_node(name, port, :inet)
  def register_node(_name, _port, _family), do: {:ok, :rand.uniform(3)}

  def port_please(name, host), do: address_please(name, host, :inet)
  def port_please(name, host, _timeout), do: address_please(name, host, :inet)

  def listen_port_please(_name, _host), do: {:ok, 0}

  def names(host), do: :erl_epmd.names(host)

  # The 4th element is hs_data.other_version, the legacy epmd-era protocol
  # version. Modern distribution (OTP 23+) negotiates the real version in-band
  # via DFLAGS — dist_util never reads other_version — so this field is
  # vestigial and a fixed 5 is safe. (There is no runtime accessor for it;
  # `:erlang.system_info(:dist_high)` does not exist.) Verified handshaking
  # across an OTP 28 → OTP 27 gap with this value.
  @dist_proto_version 5

  @doc """
  Resolve `name@host` to its pinned `{ip, port}` from the endpoint table, or defer
  to the real `:erl_epmd` when the name is not pinned (plain routable nodes).
  """
  def address_please(name, host, family) do
    case lookup(:"#{name}@#{host}") do
      {ip, port} -> {:ok, ip, port, @dist_proto_version}
      nil -> :erl_epmd.address_please(name, host, family)
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
