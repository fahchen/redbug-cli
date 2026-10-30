defmodule Server.Tui.Settings do
  @moduledoc """
  The settings screen of the Terra TUI. The rows and keys follow
  `tui/src/SettingsScreen.tsx`. The screen calls `Server.Config` directly, as
  `Server.Stores.SettingsRoot` does, and reads the settings in `view/3`, so it
  always shows the current data. The overlay of the Bun screen is a full-screen
  page. The `theme` setting cycles and persists, but the Terra TUI has only the
  tokyo-night colors (`docs/terra-gaps.md`).
  """

  import Terra.View

  alias Server.Config
  alias Server.Tui.{Theme, Ui}
  alias Terra.Widget

  # tui/src/theme.ts:98-446 (the keys of `themes`)
  @themes ~w(pico-8 dark light tokyo-night tokyo-storm tokyo-moon tokyo-day catppuccin-mocha dracula nord gruvbox-dark catppuccin-latte catppuccin-frappe catppuccin-macchiato rose-pine solarized one-dark everforest monokai)
  # tui/src/SettingsScreen.tsx:16-17
  @columns [:name, :pid, :mfa, :info]
  @sorts ~w(ts_desc ts_asc kind_asc kind_desc pid_asc mfa_asc)
  # theme, sort, 4 columns, limits, show hints, console timeout
  @row_count 9
  # The defaults of Server.Config: a stored settings map can miss a key.
  @defaults %{
    columns: %{},
    default_sort: "ts_desc",
    default_limits: %{keep: 500, time: 900, msgs: 10_000},
    theme: "tokyo-night",
    show_hints: true,
    console_timeout: 15_000
  }

  @doc "The screen state."
  def new, do: %{sel: 0, page: :main}

  # --- keys ---

  @doc "Handles a key. `:close` goes back."
  def key(_key, %{page: :help} = s), do: {:ok, %{s | page: :main}}
  def key(key, %{page: {:input, _, _, _}} = s), do: input_key(key, s)

  # tui/src/SettingsScreen.tsx:83-115
  def key(:esc, _s), do: :close
  def key({:char, "?"}, s), do: {:ok, %{s | page: :help}}

  def key(k, s) when k in [:down, {:char, "j"}],
    do: {:ok, %{s | sel: min(s.sel + 1, @row_count - 1)}}

  def key(k, s) when k in [:up, {:char, "k"}], do: {:ok, %{s | sel: max(s.sel - 1, 0)}}

  def key(k, s) when k in [{:char, " "}, :enter, :right, {:char, "l"}],
    do: {:ok, act(s, settings())}

  def key(_key, s), do: {:ok, s}

  # tui/src/SettingsScreen.tsx:61-75
  defp act(%{sel: 0} = s, settings), do: update(s, %{theme: cycle(@themes, settings.theme)})

  defp act(%{sel: 1} = s, settings),
    do: update(s, %{default_sort: cycle(@sorts, settings.default_sort)})

  defp act(%{sel: sel} = s, settings) when sel in 2..5 do
    column = Enum.at(@columns, sel - 2)
    update(s, %{columns: %{column => not Map.get(settings.columns, column, true)}})
  end

  defp act(%{sel: 6} = s, settings) do
    l = settings.default_limits
    value = "#{l.keep} #{l.time} #{l.msgs}"
    %{s | page: {:input, :limits, value, String.length(value)}}
  end

  defp act(%{sel: 7} = s, settings), do: update(s, %{show_hints: not settings.show_hints})

  # The input opens empty (the current value is the placeholder), so a key
  # replaces the value and does not append to it.
  defp act(%{sel: 8} = s, _settings), do: %{s | page: {:input, :timeout, "", 0}}

  defp update(s, attrs) do
    Config.update_settings(attrs)
    s
  end

  defp cycle(values, current) do
    case Enum.find_index(values, &(&1 == current)) do
      nil -> hd(values)
      i -> Enum.at(values, rem(i + 1, length(values)))
    end
  end

  defp input_key(key, %{page: {:input, kind, value, cursor}} = s) do
    case Widget.input_event(key, value, cursor) do
      {:edit, value, cursor} -> {:ok, %{s | page: {:input, kind, value, cursor}}}
      {:submit, value} -> {:ok, submit(kind, String.trim(value), %{s | page: :main})}
      :cancel -> {:ok, %{s | page: :main}}
      :ignore -> {:ok, s}
    end
  end

  # tui/src/limits.ts: "keep time msgs"; a bad text changes nothing.
  defp submit(:limits, text, s) do
    case text |> String.split() |> Enum.map(&Integer.parse/1) do
      [{keep, ""}, {time, ""}, {msgs, ""}] when keep >= 0 and time >= 0 and msgs >= 0 ->
        update(s, %{default_limits: %{keep: keep, time: time, msgs: msgs}})

      _ ->
        s
    end
  end

  # tui/src/SettingsScreen.tsx:186-196: seconds, as parseInt reads them; a
  # blank or bad text keeps the value.
  defp submit(:timeout, text, s) do
    case Integer.parse(text) do
      {secs, _rest} when secs > 0 -> update(s, %{console_timeout: secs * 1000})
      _ -> s
    end
  end

  defp settings, do: Map.merge(@defaults, Config.settings())

  # --- views ---

  @doc "The view of the screen."
  def view(%{page: :help}, width, height),
    do: Ui.page(width, height, "Help · settings", Ui.help_lines(help_rows()))

  def view(%{page: {:input, kind, value, cursor}}, width, height),
    do: input_view(kind, value, cursor, width, height)

  def view(s, width, height) do
    settings = settings()
    cols = settings.columns
    l = settings.default_limits
    check = fn on? -> if on?, do: "[x]", else: "[ ]" end

    rows = [
      {"Theme", "#{settings.theme} (only tokyo-night colors)"},
      {"Default sort", settings.default_sort},
      :gap,
      {"Col · name", check.(Map.get(cols, :name, true))},
      {"Col · pid", check.(Map.get(cols, :pid, true))},
      {"Col · mfa", check.(Map.get(cols, :mfa, true))},
      {"Col · info", check.(Map.get(cols, :info, true))},
      :gap,
      {"Default limits", "keep #{l.keep} · time #{l.time}s · msgs #{l.msgs}"},
      :gap,
      {"Show hints", check.(settings.show_hints)},
      :gap,
      {"Console timeout", "#{round(settings.console_timeout / 1000)}s"}
    ]

    lines =
      rows
      |> Enum.map_reduce(0, fn
        :gap, i -> {text(""), i}
        {label, value}, i -> {row(label, value, i == s.sel), i + 1}
      end)
      |> elem(0)

    Ui.page(
      width,
      height,
      "Settings",
      lines ++
        [
          text(""),
          text("ts is always shown; the kind glyph rides in front of mfa.",
            fg: Theme.color(:muted)
          ),
          text(""),
          hstack(Ui.hints("j/k move · space toggle · ? help · esc close", max(width - 6, 1)))
        ]
    )
  end

  defp row(label, value, selected?) do
    bg = if selected?, do: [bg: Theme.color(:element)], else: []

    hstack([
      text(Ui.fit(label, 16), [fg: Theme.color(:muted)] ++ bg),
      text(value <> " ", [fg: Theme.color(if selected?, do: :text, else: :muted)] ++ bg)
    ])
  end

  defp input_view(kind, value, cursor, width, height) do
    current = round(settings().console_timeout / 1000)

    {title, placeholder} =
      case kind do
        :limits ->
          {"Default limits — keep time msgs (space-separated)", "500 900 10000"}

        :timeout ->
          {"Console timeout — seconds (current #{current}s · blank = keep)", "#{current}"}
      end

    Ui.page(width, height, title, [
      Widget.input(value, cursor: cursor, placeholder: placeholder),
      text(""),
      text("Enter save · Esc cancel", fg: Theme.color(:muted))
    ])
  end

  # tui/src/SettingsScreen.tsx:153-171
  defp help_rows do
    [
      {"j / k", "move"},
      {"space / enter / right / l", "toggle or cycle value"},
      {"esc", "close"}
    ]
  end
end
