defmodule Server.Config do
  @moduledoc """
  Single source of truth for redbug-cli state.

  Persisted config (`:nodes`, `:presets`, `:settings`) plus runtime state
  (`:connected`, `:session_status`) live in a named ETS table owned by this
  GenServer. Stores read the table directly via the `nodes/0`, `presets/0`,
  `settings/0`, … helpers (no GenServer round-trip) and subscribe to the
  `"config"` PubSub topic; every mutation here writes ETS, persists the config
  slice to the XDG config path (mode 0600, see `path/0`), then broadcasts
  `{:config_updated}` so subscribed stores re-read and re-render.

  Remote-node side-effects (`Node.connect_node/1`, later `:redbug`) run inside
  this process — stores forward intent here and never touch distribution
  directly.
  """

  use GenServer

  require Logger

  @table :redbug_config
  @endpoints :redbug_endpoints
  @topic "config"
  @pubsub Server.PubSub

  @default_settings %{
    columns: %{name: true, pid: true, mfa: true, info: true},
    default_sort: "ts_desc",
    default_limits: %{keep: 500, time: 900, msgs: 10_000},
    theme: "dark",
    show_hints: true
  }

  # --- lifecycle ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # --- reads (hit ETS directly) ---

  @doc "All target nodes (config or env), each merged with runtime `connected`/session `status`."
  def nodes do
    connected = lookup(:connected, MapSet.new())
    statuses = lookup(:session_status, %{})

    for node <- nodes_raw() do
      sessions =
        for s <- node.sessions do
          Map.put(s, :status, Map.get(statuses, s.id, "stopped"))
        end

      node
      |> Map.put(:connected, MapSet.member?(connected, node.id))
      |> Map.put(:sessions, sessions)
    end
  end

  @doc "True when nodes come from `REDBUG_NODES` (read-only env mode, the whole list)."
  def env_mode?, do: lookup(:env_nodes, []) != []

  # Raw nodes with no runtime merge. In env mode this is the injected list
  # (sessions pulled from the persisted `:env_sessions` map by node name, so a
  # node that drops out of REDBUG_NODES auto-hides while keeping its sessions);
  # otherwise the persisted config nodes.
  defp nodes_raw do
    if env_mode?() do
      by_name = lookup(:env_sessions, %{})

      for nd <- lookup(:env_nodes, []) do
        %{
          id: nd.id,
          name: nd.name,
          cookie: nd.cookie,
          source: "env",
          sessions: Map.get(by_name, nd.name, [])
        }
      end
    else
      for node <- lookup(:nodes, []), do: Map.put(node, :source, "config")
    end
  end

  def presets, do: lookup(:presets, [])

  def snippets, do: lookup(:snippets, [])

  def settings, do: lookup(:settings, @default_settings)

  @doc "Raw node (config or env, no runtime merge), or nil."
  def fetch_node(node_id), do: Enum.find(nodes_raw(), &(&1.id == node_id))

  def cookie(node_id) do
    case fetch_node(node_id) do
      nil -> nil
      node -> Map.get(node, :cookie)
    end
  end

  # --- mutations (serialized through GenServer) ---

  def add_node(attrs), do: GenServer.call(__MODULE__, {:add_node, attrs})
  def update_node(id, attrs), do: GenServer.call(__MODULE__, {:update_node, id, attrs})
  def delete_node(id), do: GenServer.call(__MODULE__, {:delete_node, id})

  def add_session(node_id, attrs), do: GenServer.call(__MODULE__, {:add_session, node_id, attrs})

  def update_session(node_id, id, attrs),
    do: GenServer.call(__MODULE__, {:update_session, node_id, id, attrs})

  def delete_session(node_id, id),
    do: GenServer.call(__MODULE__, {:delete_session, node_id, id})

  def add_preset(attrs), do: GenServer.call(__MODULE__, {:add_preset, attrs})
  def update_preset(id, attrs), do: GenServer.call(__MODULE__, {:update_preset, id, attrs})
  def delete_preset(id), do: GenServer.call(__MODULE__, {:delete_preset, id})

  def add_snippet(attrs), do: GenServer.call(__MODULE__, {:add_snippet, attrs})
  def update_snippet(id, attrs), do: GenServer.call(__MODULE__, {:update_snippet, id, attrs})
  def delete_snippet(id), do: GenServer.call(__MODULE__, {:delete_snippet, id})

  def update_settings(attrs), do: GenServer.call(__MODULE__, {:update_settings, attrs})

  # --- remote-node side-effects (run inside the GenServer) ---

  def connect_node(id), do: GenServer.call(__MODULE__, {:connect_node, id})
  def disconnect_node(id), do: GenServer.call(__MODULE__, {:disconnect_node, id})

  @doc "Set a session's runtime status (\"running\"/\"stopped\"); not persisted."
  def set_session_status(session_id, status),
    do: GenServer.call(__MODULE__, {:set_session_status, session_id, status})

  @doc "Generates a short random id for a config entity."
  def gen_id, do: 8 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

  # --- GenServer callbacks ---

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :protected, read_concurrency: true])
    # public: the kernel's connect path reads this via Server.Epmd; it's an in-VM
    # dial table (ip:port only, no secrets), so writers beyond Config are harmless.
    :ets.new(@endpoints, [:named_table, :public, read_concurrency: true])

    # REDBUG_NODES → dial-endpoint table (read by Server.Epmd on connect) + the
    # read-only node defs surfaced in the tree.
    {env_nodes, endpoints} = parse_env_nodes()
    for {key, endpoint} <- endpoints, do: :ets.insert(@endpoints, {key, endpoint})

    config = load()
    :ets.insert(@table, {:nodes, config.nodes})
    :ets.insert(@table, {:presets, config.presets})
    :ets.insert(@table, {:snippets, config.snippets})
    :ets.insert(@table, {:settings, config.settings})
    :ets.insert(@table, {:env_sessions, config.env_sessions})
    :ets.insert(@table, {:env_nodes, env_nodes})
    :ets.insert(@table, {:connected, MapSet.new()})
    :ets.insert(@table, {:session_status, %{}})

    {:ok, %{}}
  end

  @impl true
  def handle_call({:add_node, attrs}, _from, state) do
    node = %{
      id: gen_id(),
      name: Map.get(attrs, :name, ""),
      cookie: Map.get(attrs, :cookie, ""),
      sessions: []
    }

    put_nodes(lookup(:nodes, []) ++ [node])
    {:reply, {:ok, node.id}, state}
  end

  def handle_call({:update_node, id, attrs}, _from, state) do
    # env nodes are read-only; only config nodes can be edited.
    unless env_id?(id) do
      nodes =
        update_in_list(lookup(:nodes, []), id, fn node ->
          node
          |> maybe_put(:name, attrs)
          |> maybe_put(:cookie, attrs)
        end)

      put_nodes(nodes)
    end

    {:reply, :ok, state}
  end

  def handle_call({:delete_node, id}, _from, state) do
    unless env_id?(id) do
      put_nodes(Enum.reject(lookup(:nodes, []), &(&1.id == id)))
      drop_connected(id)
    end

    {:reply, :ok, state}
  end

  def handle_call({:add_session, node_id, attrs}, _from, state) do
    session = %{
      id: gen_id(),
      name: Map.get(attrs, :name, "session"),
      traces: Map.get(attrs, :traces, []),
      limits: Map.get(attrs, :limits, settings().default_limits)
    }

    if env_id?(node_id) do
      update_env_sessions(env_name(node_id), &(&1 ++ [session]))
    else
      put_nodes(
        update_in_list(lookup(:nodes, []), node_id, fn node ->
          %{node | sessions: node.sessions ++ [session]}
        end)
      )
    end

    {:reply, {:ok, session.id}, state}
  end

  def handle_call({:update_session, node_id, id, attrs}, _from, state) do
    if env_id?(node_id) do
      update_env_sessions(env_name(node_id), &update_in_list(&1, id, fn s -> Map.merge(s, attrs) end))
    else
      put_nodes(
        update_in_list(lookup(:nodes, []), node_id, fn node ->
          %{node | sessions: update_in_list(node.sessions, id, &Map.merge(&1, attrs))}
        end)
      )
    end

    {:reply, :ok, state}
  end

  def handle_call({:delete_session, node_id, id}, _from, state) do
    if env_id?(node_id) do
      update_env_sessions(env_name(node_id), &Enum.reject(&1, fn s -> s.id == id end))
    else
      put_nodes(
        update_in_list(lookup(:nodes, []), node_id, fn node ->
          %{node | sessions: Enum.reject(node.sessions, &(&1.id == id))}
        end)
      )
    end

    {:reply, :ok, state}
  end

  def handle_call({:add_preset, attrs}, _from, state) do
    preset = %{
      id: gen_id(),
      name: Map.get(attrs, :name, "preset"),
      traces: Map.get(attrs, :traces, []),
      limits: Map.get(attrs, :limits, settings().default_limits)
    }

    put_presets(lookup(:presets, []) ++ [preset])
    {:reply, {:ok, preset.id}, state}
  end

  def handle_call({:update_preset, id, attrs}, _from, state) do
    put_presets(update_in_list(lookup(:presets, []), id, &Map.merge(&1, attrs)))
    {:reply, :ok, state}
  end

  def handle_call({:delete_preset, id}, _from, state) do
    put_presets(Enum.reject(lookup(:presets, []), &(&1.id == id)))
    {:reply, :ok, state}
  end

  def handle_call({:add_snippet, attrs}, _from, state) do
    snippet = %{
      id: gen_id(),
      name: Map.get(attrs, :name, "snippet"),
      code: Map.get(attrs, :code, "")
    }

    put_snippets(lookup(:snippets, []) ++ [snippet])
    {:reply, {:ok, snippet.id}, state}
  end

  def handle_call({:update_snippet, id, attrs}, _from, state) do
    put_snippets(update_in_list(lookup(:snippets, []), id, &Map.merge(&1, attrs)))
    {:reply, :ok, state}
  end

  def handle_call({:delete_snippet, id}, _from, state) do
    put_snippets(Enum.reject(lookup(:snippets, []), &(&1.id == id)))
    {:reply, :ok, state}
  end

  def handle_call({:update_settings, attrs}, _from, state) do
    :ets.insert(@table, {:settings, deep_merge(settings(), attrs)})
    persist_and_broadcast()
    {:reply, :ok, state}
  end

  def handle_call({:connect_node, id}, _from, state) do
    result =
      case fetch_node(id) do
        nil ->
          {:error, :not_found}

        node ->
          target = String.to_atom(node.name)
          if cookie = node[:cookie], do: Node.set_cookie(target, String.to_atom(cookie))

          case Node.connect(target) do
            true ->
              add_connected(id)
              :ok

            other ->
              Logger.warning("connect #{node.name} failed: #{inspect(other)}")
              {:error, :unreachable}
          end
      end

    {:reply, result, state}
  end

  def handle_call({:disconnect_node, id}, _from, state) do
    case fetch_node(id) do
      nil -> :ok
      node -> Node.disconnect(String.to_atom(node.name))
    end

    drop_connected(id)
    {:reply, :ok, state}
  end

  def handle_call({:set_session_status, session_id, status}, _from, state) do
    statuses = lookup(:session_status, %{})
    :ets.insert(@table, {:session_status, Map.put(statuses, session_id, status)})
    broadcast()
    {:reply, :ok, state}
  end

  # --- ETS write helpers (run in GenServer) ---

  defp put_nodes(nodes) do
    :ets.insert(@table, {:nodes, nodes})
    persist_and_broadcast()
  end

  defp put_presets(presets) do
    :ets.insert(@table, {:presets, presets})
    persist_and_broadcast()
  end

  defp put_snippets(snippets) do
    :ets.insert(@table, {:snippets, snippets})
    persist_and_broadcast()
  end

  # Sessions under env nodes live in a name-keyed map (env nodes themselves are
  # rebuilt from REDBUG_NODES each boot, so their sessions persist separately and
  # survive the node dropping out / coming back).
  defp update_env_sessions(name, fun) do
    map = lookup(:env_sessions, %{})
    :ets.insert(@table, {:env_sessions, Map.put(map, name, fun.(Map.get(map, name, [])))})
    persist_and_broadcast()
  end

  defp env_id?(id), do: is_binary(id) and String.starts_with?(id, "env:")
  defp env_name("env:" <> name), do: name

  defp add_connected(id) do
    connected = lookup(:connected, MapSet.new())

    # connect_node/1 runs on every console execution; only write + fan out a
    # {:config_updated} when membership actually changes, else each run triggers
    # a global re-render of every subscribed store.
    unless MapSet.member?(connected, id) do
      :ets.insert(@table, {:connected, MapSet.put(connected, id)})
      broadcast()
    end
  end

  defp drop_connected(id) do
    :ets.insert(@table, {:connected, MapSet.delete(lookup(:connected, MapSet.new()), id)})
    broadcast()
  end

  defp persist_and_broadcast do
    save(%{
      nodes: lookup(:nodes, []),
      presets: lookup(:presets, []),
      snippets: lookup(:snippets, []),
      settings: settings(),
      env_sessions: lookup(:env_sessions, %{})
    })
    broadcast()
  end

  defp broadcast, do: Phoenix.PubSub.broadcast(@pubsub, @topic, {:config_updated})

  # --- list helpers ---

  defp update_in_list(list, id, fun) do
    Enum.map(list, fn item -> if item.id == id, do: fun.(item), else: item end)
  end

  defp maybe_put(map, key, attrs) do
    case Map.fetch(attrs, key) do
      {:ok, value} -> Map.put(map, key, value)
      :error -> map
    end
  end

  defp deep_merge(left, right) do
    Map.merge(left, right, fn
      _k, %{} = l, %{} = r -> deep_merge(l, r)
      _k, _l, r -> r
    end)
  end

  defp lookup(key, default) do
    case :ets.lookup(@table, key) do
      [{^key, value}] -> value
      [] -> default
    end
  end

  # --- subscription (called by stores) ---

  @doc "Subscribe the calling process to config-change broadcasts."
  def subscribe, do: Phoenix.PubSub.subscribe(@pubsub, @topic)

  # --- JSON persistence (config slice only, 0600) ---

  @doc """
  Absolute path to the config file.

  Override with `:config_path` (tests). Otherwise XDG:
  `$XDG_CONFIG_HOME/redbug/config.json`, falling back to
  `~/.config/redbug/config.json`.
  """
  def path do
    Application.get_env(:server, :config_path) ||
      Path.join(config_home(), "redbug/config.json")
  end

  defp config_home do
    case System.get_env("XDG_CONFIG_HOME") do
      dir when is_binary(dir) and dir != "" -> dir
      _ -> Path.expand("~/.config")
    end
  end

  defp load do
    case File.read(path()) do
      {:ok, body} ->
        case Jason.decode(body) do
          {:ok, json} -> from_json(json)
          {:error, _} -> default_config()
        end

      {:error, _} ->
        default_config()
    end
  end

  defp save(config) do
    dir = Path.dirname(path())
    File.mkdir_p!(dir)
    File.chmod(dir, 0o700)
    File.write!(path(), Jason.encode!(to_json(config), pretty: true))
    File.chmod(path(), 0o600)
  end

  defp default_config,
    do: %{nodes: [], presets: [], snippets: [], settings: @default_settings, env_sessions: %{}}

  # --- REDBUG_NODES parsing ---

  # "name@host|dial_ip:port|cookie, …" → ({env_nodes, endpoints}).
  # endpoints maps the node atom to its `{ip_tuple, port}` dial target.
  defp parse_env_nodes do
    case System.get_env("REDBUG_NODES") do
      raw when is_binary(raw) and raw != "" ->
        raw
        |> String.split(",", trim: true)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
        |> Enum.reduce({[], %{}}, fn entry, {defs, eps} ->
          case parse_env_entry(entry) do
            {:ok, name, endpoint, cookie} ->
              nd = %{id: "env:" <> name, name: name, cookie: cookie}
              {defs ++ [nd], Map.put(eps, String.to_atom(name), endpoint)}

            :error ->
              Logger.warning("REDBUG_NODES: ignoring malformed entry #{inspect(entry)}")
              {defs, eps}
          end
        end)

      _ ->
        {[], %{}}
    end
  end

  defp parse_env_entry(entry) do
    case String.split(entry, "|") do
      [name, dial | rest] ->
        name = String.trim(name)

        with true <- String.contains?(name, "@"),
             {:ok, endpoint} <- parse_dial(dial) do
          {:ok, name, endpoint, rest |> List.first() |> normalize_cookie()}
        else
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp parse_dial(dial) do
    with [ip, port] <- dial |> String.trim() |> String.split(":"),
         {:ok, addr} <- :inet.parse_address(String.to_charlist(ip)),
         {p, ""} <- Integer.parse(port) do
      {:ok, {addr, p}}
    else
      _ -> :error
    end
  end

  defp normalize_cookie(cookie) when is_binary(cookie) do
    case String.trim(cookie) do
      "" -> default_cookie()
      c -> c
    end
  end

  defp normalize_cookie(_), do: default_cookie()

  defp default_cookie do
    case Node.get_cookie() do
      :nocookie -> ""
      c -> Atom.to_string(c)
    end
  end

  # --- JSON <-> internal (explicit, atom-safe) ---

  defp from_json(json) do
    %{
      nodes: json |> Map.get("nodes", []) |> Enum.map(&node_from_json/1),
      presets: json |> Map.get("presets", []) |> Enum.map(&preset_from_json/1),
      snippets: json |> Map.get("snippets", []) |> Enum.map(&snippet_from_json/1),
      settings: json |> Map.get("settings") |> settings_from_json(),
      env_sessions: json |> Map.get("env_sessions", %{}) |> env_sessions_from_json()
    }
  end

  defp env_sessions_from_json(map) when is_map(map) do
    Map.new(map, fn {name, sessions} -> {name, Enum.map(sessions, &session_from_json/1)} end)
  end

  defp env_sessions_from_json(_), do: %{}

  defp snippet_from_json(j) do
    %{
      id: Map.get(j, "id", gen_id()),
      name: Map.get(j, "name", "snippet"),
      code: Map.get(j, "code", "")
    }
  end

  defp node_from_json(j) do
    %{
      id: Map.get(j, "id", gen_id()),
      name: Map.get(j, "name", ""),
      cookie: Map.get(j, "cookie", ""),
      sessions: j |> Map.get("sessions", []) |> Enum.map(&session_from_json/1)
    }
  end

  defp session_from_json(j) do
    %{
      id: Map.get(j, "id", gen_id()),
      name: Map.get(j, "name", "session"),
      traces: j |> Map.get("traces", []) |> Enum.map(&rtp_from_json/1),
      limits: j |> Map.get("limits") |> limits_from_json()
    }
  end

  defp preset_from_json(j) do
    %{
      id: Map.get(j, "id", gen_id()),
      name: Map.get(j, "name", "preset"),
      traces: j |> Map.get("traces", []) |> Enum.map(&rtp_from_json/1),
      limits: j |> Map.get("limits") |> limits_from_json()
    }
  end

  defp rtp_from_json(j) do
    %{
      id: Map.get(j, "id", gen_id()),
      text: Map.get(j, "text", ""),
      enabled: Map.get(j, "enabled", true)
    }
  end

  defp limits_from_json(nil), do: @default_settings.default_limits

  defp limits_from_json(j) do
    %{
      keep: Map.get(j, "keep", 500),
      time: Map.get(j, "time", 900),
      msgs: Map.get(j, "msgs", 10_000)
    }
  end

  defp settings_from_json(nil), do: @default_settings

  defp settings_from_json(j) do
    cols = Map.get(j, "columns", %{})

    %{
      columns: %{
        name: Map.get(cols, "name", true),
        pid: Map.get(cols, "pid", true),
        mfa: Map.get(cols, "mfa", true),
        info: Map.get(cols, "info", true)
      },
      default_sort: Map.get(j, "default_sort", @default_settings.default_sort),
      default_limits: j |> Map.get("default_limits") |> limits_from_json(),
      theme: Map.get(j, "theme", @default_settings.theme),
      show_hints: Map.get(j, "show_hints", @default_settings.show_hints)
    }
  end

  # Internal maps already use atom keys; Jason encodes atom keys as strings.
  defp to_json(config), do: config
end
