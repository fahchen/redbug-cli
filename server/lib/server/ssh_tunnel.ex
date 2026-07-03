defmodule Server.SshTunnel do
  @moduledoc """
  Reaches a container-hosted node over SSH without exposing any port.

  For an ssh-backed node (`ssh_host`/`ssh_user`/`container` set), `open/1`:

    1. `:ssh.connect`s to the host (ssh-agent first, then a key file; publickey
       only, so a missing key fails cleanly instead of dropping to a password
       prompt);
    2. over that same connection, `exec`s `docker inspect` + `epmd -names` to
       discover the container's bridge IP and the node's (random) distribution
       port;
    3. opens an `ssh -L`-style local forward to `<container-ip>:<dist-port>`
       (`tcpip_tunnel_to_server`, local port 0 → OS-assigned); and
    4. pins `node@host → {127.0.0.1, local_port}` in the `:redbug_endpoints`
       table so `Server.Epmd` dials the node straight through the tunnel.

  Direct connect (no bastion): `:ssh` does not read `~/.ssh/config`. One
  GenServer owns every live tunnel keyed by node id; if a connection drops, its
  endpoint is unpinned so a stale tunnel can't mask a dead node.
  """

  use GenServer
  require Logger

  # :ssh / :ssh_connection are OTP apps loaded at runtime (extra_applications),
  # not visible to the compile-time xref check.
  @compile {:no_warn_undefined, [:ssh, :ssh_connection]}

  @endpoints :redbug_endpoints
  @ssh_port 22
  # ponytail: fixed 22; add a per-node ssh_port field if a non-standard port
  # ever comes up (`:ssh` can't fall back to ~/.ssh/config for it).

  def start_link(_opts \\ []), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  @doc "Open (or reuse) a tunnel for an ssh-backed node and pin its endpoint."
  @spec open(map()) :: :ok | {:error, term()}
  def open(node), do: GenServer.call(__MODULE__, {:open, node}, 30_000)

  @doc "Tear the node's tunnel down and unpin its endpoint."
  @spec close(String.t()) :: :ok
  def close(node_id), do: GenServer.call(__MODULE__, {:close, node_id})

  # --- GenServer ---

  @impl true
  def init(_) do
    {:ok, _} = Application.ensure_all_started(:ssh)
    {:ok, %{tunnels: %{}}}
  end

  @impl true
  def handle_call({:open, node}, _from, state) do
    if Map.has_key?(state.tunnels, node.id) do
      {:reply, :ok, state}
    else
      case establish(node) do
        {:ok, conn, node_atom} ->
          mon = Process.monitor(conn)
          tunnel = %{conn: conn, mon: mon, node_atom: node_atom}
          {:reply, :ok, put_in(state.tunnels[node.id], tunnel)}

        {:error, _} = err ->
          {:reply, err, state}
      end
    end
  end

  def handle_call({:close, node_id}, _from, state) do
    {:reply, :ok, teardown(state, node_id)}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    case Enum.find(state.tunnels, fn {_id, t} -> t.mon == ref end) do
      {node_id, t} ->
        Logger.warning("ssh tunnel for #{t.node_atom} dropped: #{inspect(reason)}")
        unpin(t.node_atom)
        {:noreply, %{state | tunnels: Map.delete(state.tunnels, node_id)}}

      nil ->
        {:noreply, state}
    end
  end

  # --- tunnel lifecycle ---

  defp establish(node) do
    with {:ok, host} <- require_field(node[:ssh_host], :no_ssh_host),
         user = node[:ssh_user] || System.get_env("USER") || "",
         {:ok, conn} <- ssh_connect(host, user),
         {:ok, ip, port} <- discover(conn, node[:container]),
         {:ok, lport} <- forward(conn, ip, port) do
      node_atom = String.to_atom(node.name)
      :ets.insert(@endpoints, {node_atom, {{127, 0, 0, 1}, lport}})
      {:ok, conn, node_atom}
    end
  end

  defp teardown(state, node_id) do
    case Map.pop(state.tunnels, node_id) do
      {nil, tunnels} ->
        %{state | tunnels: tunnels}

      {t, tunnels} ->
        Process.demonitor(t.mon, [:flush])
        unpin(t.node_atom)
        :ssh.close(t.conn)
        %{state | tunnels: tunnels}
    end
  end

  defp unpin(node_atom) do
    if :ets.whereis(@endpoints) != :undefined, do: :ets.delete(@endpoints, node_atom)
  end

  # --- ssh ---

  defp ssh_connect(host, user) do
    base = [
      user: String.to_charlist(user),
      auth_methods: ~c"publickey",
      # ponytail: dev tool, local-trusted target; TODO honor ~/.ssh/known_hosts
      # with silently_accept_hosts as an opt-out.
      silently_accept_hosts: true,
      save_accepted_host: false,
      connect_timeout: 10_000
    ]

    # ssh-agent first (only if one is actually running, else :ssh drops to a
    # password attempt that crashes), then a key file under ~/.ssh.
    attempts =
      [
        if(System.get_env("SSH_AUTH_SOCK"), do: [{:key_cb, {:ssh_agent, []}} | base]),
        [{:user_dir, ssh_dir()} | base]
      ]
      |> Enum.reject(&is_nil/1)

    Enum.reduce_while(attempts, {:error, :ssh_auth}, fn opts, _acc ->
      case :ssh.connect(String.to_charlist(host), @ssh_port, opts, 10_000) do
        {:ok, conn} -> {:halt, {:ok, conn}}
        {:error, reason} -> {:cont, {:error, {:ssh_connect, reason}}}
      end
    end)
  end

  defp ssh_dir, do: String.to_charlist(Path.expand("~/.ssh"))

  defp forward(conn, ip, port) do
    case :ssh.tcpip_tunnel_to_server(conn, ~c"127.0.0.1", 0, String.to_charlist(ip), port, 10_000) do
      {:ok, lport} -> {:ok, lport}
      {:error, reason} -> {:error, {:ssh_forward, reason}}
    end
  end

  # --- discovery (over the same ssh connection) ---

  defp discover(conn, container) do
    with {:ok, svc} <- safe_container(container),
         {:ok, out, 0} <- exec(conn, discover_cmd(svc)),
         {:ok, ip} <- parse_ip(out),
         {:ok, port} <- parse_port(out) do
      {:ok, ip, port}
    else
      {:ok, _out, status} -> {:error, {:discovery_exit, status}}
      {:error, _} = err -> err
      other -> {:error, {:discovery, other}}
    end
  end

  # Kamal labels the app container `service=<name> role=web`; fall back to a bare
  # name/id match. `svc` is validated (safe_container/1) before interpolation.
  defp discover_cmd(svc) do
    ~c"""
    set -e
    C=$(docker ps --filter label=service=#{svc} --filter label=role=web -q | head -1)
    [ -n "$C" ] || C=$(docker ps --filter name=#{svc} -q | head -1)
    [ -n "$C" ] || { echo "no container for #{svc}" >&2; exit 3; }
    docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{println}}{{end}}' "$C" | grep . | head -1
    # epmd is often not on PATH in a release image (it lives under erts-*/bin), so
    # locate it before asking for the node's port.
    docker exec "$C" sh -c 'E=$(command -v epmd 2>/dev/null || ls -d /app/erts-*/bin/epmd 2>/dev/null | head -1); exec "$E" -names'
    """
  end

  defp exec(conn, cmd) do
    with {:ok, ch} <- :ssh_connection.session_channel(conn, 5_000),
         :success <- :ssh_connection.exec(conn, ch, cmd, 5_000) do
      collect(conn, ch, "", nil)
    else
      other -> {:error, {:exec, other}}
    end
  end

  defp collect(conn, ch, acc, status) do
    receive do
      {:ssh_cm, ^conn, {:data, ^ch, _type, data}} -> collect(conn, ch, acc <> data, status)
      {:ssh_cm, ^conn, {:exit_status, ^ch, s}} -> collect(conn, ch, acc, s)
      {:ssh_cm, ^conn, {:eof, ^ch}} -> collect(conn, ch, acc, status)
      {:ssh_cm, ^conn, {:closed, ^ch}} -> {:ok, acc, status || 0}
    after
      8_000 -> {:error, :exec_timeout}
    end
  end

  # --- pure parsing (see ssh_tunnel_test) ---

  @doc false
  def safe_container(c) when is_binary(c) do
    if Regex.match?(~r/\A[A-Za-z0-9._-]+\z/, c),
      do: {:ok, c},
      else: {:error, :bad_container}
  end

  def safe_container(_), do: {:error, :no_container}

  @doc false
  def parse_ip(out) do
    case Regex.run(~r/(\d{1,3}(?:\.\d{1,3}){3})/, out) do
      [_, ip] -> {:ok, ip}
      _ -> {:error, :no_ip}
    end
  end

  @doc false
  def parse_port(out) do
    case Regex.run(~r/at port (\d+)/, out) do
      [_, p] -> {:ok, String.to_integer(p)}
      _ -> {:error, :no_port}
    end
  end

  defp require_field(nil, err), do: {:error, err}
  defp require_field("", err), do: {:error, err}
  defp require_field(v, _err), do: {:ok, v}
end
