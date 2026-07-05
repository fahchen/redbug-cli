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

  @doc """
  Open (or reuse) a tunnel for an ssh-backed node and pin its endpoint.

  Returns `{:ok, node_name, cookie}` — the actual node to dial and the cookie to
  use. For a shortname controller the name is discovered (`<sname>@<host>`, since
  the caller can't know a release's `-sname` host); the cookie is read from the
  release when the node has none set.
  """
  @spec open(map()) :: {:ok, String.t(), String.t() | nil} | {:error, term()}
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
    case Map.get(state.tunnels, node.id) do
      %{name: name, cookie: cookie} ->
        {:reply, {:ok, name, cookie}, state}

      nil ->
        case establish(node) do
          {:ok, conn, node_atom, name, cookie} ->
            mon = Process.monitor(conn)
            tunnel = %{conn: conn, mon: mon, node_atom: node_atom, name: name, cookie: cookie}
            {:reply, {:ok, name, cookie}, put_in(state.tunnels[node.id], tunnel)}

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
         {:ok, info} <- discover(conn, node),
         :ok <- check_name_mode(info.mode),
         name = resolve_name(node, info),
         {:ok, lport} <- forward(conn, info.ip, info.port) do
      node_atom = String.to_atom(name)
      :ets.insert(@endpoints, {node_atom, {{127, 0, 0, 1}, lport}})
      {:ok, conn, node_atom, name, pick_cookie(node, info)}
    end
  end

  # Prefer the node's own name off its beam args: `-name app@host` is a full
  # longname atom; `-sname app` (or the epmd short name) is paired with the
  # discovered short host. Fall back to the name the user entered.
  defp resolve_name(node, info) do
    short = info.name || info.sname

    cond do
      is_binary(info.name) and String.contains?(info.name, "@") -> info.name
      is_binary(short) and info.host not in [nil, ""] -> "#{short}@#{info.host}"
      true -> node.name
    end
  end

  # Erlang can't connect a longname node to a shortname one (or vice versa) — it's
  # a VM-global mode. Catch the mismatch here with a clear reason instead of letting
  # Node.connect fail with an opaque "illegal hostname".
  defp check_name_mode(mode) do
    controller_long = :net_kernel.longnames()

    cond do
      mode == "short" and controller_long -> {:error, {:name_mode_mismatch, :short}}
      mode == "long" and controller_long == false -> {:error, {:name_mode_mismatch, :long}}
      true -> :ok
    end
  end

  defp pick_cookie(node, info) do
    case node[:cookie] do
      c when is_binary(c) and c != "" -> c
      _ -> info.cookie
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

  # The node runs either in a container (Kamal/Docker) or straight on the host (a
  # release under systemd, etc.). A filled `container` uses docker discovery;
  # blank means host-native discovery. Each path stays a single exec (one
  # channel), which some sshd setups need.
  defp discover(conn, node) do
    with {:ok, cmd} <- discover_cmd(node),
         {:ok, out, 0} <- exec(conn, cmd),
         {:ok, ip} <- parse_ip(out),
         own = own_shortname(out),
         {:ok, port} <- parse_port(out, own) do
      {:ok,
       %{
         ip: ip,
         port: port,
         name: parse_name(out),
         sname: parse_sname(out),
         host: parse_host(out),
         cookie: parse_cookie(out),
         mode: parse_mode(out)
       }}
    else
      {:ok, _out, status} -> {:error, {:discovery_exit, status}}
      {:error, _} = err -> err
      other -> {:error, {:discovery, other}}
    end
  end

  # Emits (either branch): the dial IP, the beam's own args (`-name`/`-sname`/
  # `-setcookie`), `epmd -names` (port), `HOST=<short hostname>`, and — docker
  # only — `COOKIE=<release cookie file>`. Interpolated search terms are
  # validated before command construction.
  @doc false
  def discover_cmd(%{container: c}) when is_binary(c) and c != "" do
    with {:ok, svc} <- safe_container(c) do
      cmd = """
    set -e
    C=
    if command -v docker >/dev/null 2>&1; then
      C=$(docker ps --filter label=service=#{svc} --filter label=role=web -q | head -1)
      [ -n "$C" ] || C=$(docker ps --filter name=#{svc} -q | head -1)
    fi
    if [ -n "$C" ]; then
      docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{println}}{{end}}' "$C" | grep . | head -1
      docker exec "$C" sh -c 'for p in /proc/[0-9]*/cmdline; do a=$(tr "\\0" " " < "$p" 2>/dev/null); case "$a" in *beam.smp*) printf "%s\\n" "$a"; break;; esac; done'
      docker exec "$C" sh -c 'E=$(command -v epmd 2>/dev/null || ls -d /app/erts-*/bin/epmd 2>/dev/null | head -1); "$E" -names'
      echo "HOST=$(docker exec "$C" hostname -s 2>/dev/null)"
      echo "COOKIE=$(docker exec "$C" sh -c 'cat /app/releases/COOKIE 2>/dev/null || cat "$HOME/.erlang.cookie" 2>/dev/null' 2>/dev/null)"
    else
      echo 127.0.0.1
      A=$(ps -eo args 2>/dev/null | grep '[b]eam\\.smp' | grep -- "#{svc}" | head -1)
      [ -n "$A" ] || A=$(ps -eo args 2>/dev/null | grep '[b]eam\\.smp' | head -1)
      [ -n "$A" ] || { echo "no container or beam for #{svc}" >&2; exit 3; }
      echo "$A"
      B=$(printf '%s' "$A" | grep -oE '[-]bindir [^ ]+' | awk '{print $2}')
      { [ -n "$B" ] && "$B/epmd" -names 2>/dev/null; } || epmd -names 2>/dev/null
      echo "HOST=$(hostname -s 2>/dev/null)"
    fi
    """
      {:ok, String.to_charlist(cmd)}
    end
  end

  def discover_cmd(node) do
    key = host_search_key(node)

    cmd = """
    set -e
    echo 127.0.0.1
    A=$(ps -eo args 2>/dev/null | grep '[b]eam\\.smp' | grep -- "#{key}" | head -1)
    [ -n "$A" ] || A=$(ps -eo args 2>/dev/null | grep '[b]eam\\.smp' | head -1)
    [ -n "$A" ] || { echo "no beam for #{key}" >&2; exit 3; }
    echo "$A"
    B=$(printf '%s' "$A" | grep -oE '[-]bindir [^ ]+' | awk '{print $2}')
    { [ -n "$B" ] && "$B/epmd" -names 2>/dev/null; } || epmd -names 2>/dev/null
    echo "HOST=$(hostname -s 2>/dev/null)"
    """

    {:ok, String.to_charlist(cmd)}
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

  defp host_search_key(node) do
    node
    |> Map.get(:name, "")
    |> to_string()
    |> String.split("@", parts: 2)
    |> hd()
    |> safe_host_search_key()
  end

  defp safe_host_search_key(key) do
    if Regex.match?(~r/\A[A-Za-z0-9._-]+\z/, key),
      do: key,
      else: ""
  end

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

  # The node's own short name off its beam args (`-name app@host` / `-sname app`),
  # used to pick the right epmd port when a transient `rem-*` remote-console node
  # is also registered (its port would otherwise win as the first `at port` match).
  defp own_shortname(out) do
    case parse_name(out) do
      name when is_binary(name) -> name |> String.split("@", parts: 2) |> hd()
      _ -> nil
    end
  end

  @doc false
  def parse_port(out, own \\ nil)

  # Prefer the epmd entry for the node's own short name (exact match), so a
  # co-registered `rem-<hex>-<name>` remote-console node can't hijack the port.
  def parse_port(out, own) when is_binary(own) do
    case Regex.run(~r/name #{Regex.escape(own)} at port (\d+)/, out) do
      [_, p] -> {:ok, String.to_integer(p)}
      _ -> parse_port(out, nil)
    end
  end

  # No known name: take the first real node's port, skipping `rem-*` shells.
  def parse_port(out, nil) do
    case Regex.run(~r/name (?!rem-)\S+ at port (\d+)/, out) do
      [_, p] -> {:ok, String.to_integer(p)}
      _ -> {:error, :no_port}
    end
  end

  @doc false
  def parse_sname(out) do
    case Regex.run(~r/name (?!rem-)(\S+) at port/, out) do
      [_, name] -> name
      _ -> nil
    end
  end

  # The node's own name off `-name app@host` / `-sname app` in the beam args.
  @doc false
  def parse_name(out) do
    case Regex.run(~r/ -s?name (\S+)/, out) do
      [_, name] -> name
      _ -> nil
    end
  end

  # Distribution mode off the beam args: -sname = shortname, -name = longname.
  @doc false
  def parse_mode(out) do
    cond do
      Regex.match?(~r/ -sname /, out) -> "short"
      Regex.match?(~r/ -name /, out) -> "long"
      true -> nil
    end
  end

  @doc false
  def parse_host(out) do
    case Regex.run(~r/^HOST=(\S+)/m, out) do
      [_, host] -> host
      _ -> nil
    end
  end

  # From a `COOKIE=` line (docker release file) or `-setcookie` in the beam args.
  @doc false
  def parse_cookie(out) do
    case Regex.run(~r/^COOKIE=(\S+)/m, out) || Regex.run(~r/-setcookie (\S+)/, out) do
      [_, cookie] -> cookie
      _ -> nil
    end
  end

  defp require_field(nil, err), do: {:error, err}
  defp require_field("", err), do: {:error, err}
  defp require_field(v, _err), do: {:ok, v}
end
