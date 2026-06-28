defmodule Server.Errors do
  @moduledoc """
  Turns the raw error terms that bubble out of trace/connect/console paths into
  a `%{message, detail}` map ready for the TUI: `message` is one human-readable
  line, `detail` is the full raw text (or `nil`) for the `e` detail overlay.

  Single source of truth for error copy — stores call `humanize/1` and assign
  the resulting `Server.Schema.AppError` straight into state, so the wire
  payload is already human-readable.
  """

  alias Server.Schema.AppError

  @messages %{
    no_enabled_rtp: "No trace pattern enabled — press space to enable at least one",
    node_not_found: "Node not found",
    session_not_found: "Session not found",
    not_found: "Node not found",
    unreachable: "Can't reach node — check address / cookie"
  }

  @spec humanize(term()) :: AppError.t()
  def humanize(reason) when is_atom(reason) do
    case Map.fetch(@messages, reason) do
      {:ok, msg} -> %AppError{message: msg, detail: nil}
      :error -> %AppError{message: "Error: #{reason}", detail: nil}
    end
  end

  # redbug/console errors arrive as already-rendered strings; keep the first
  # line as the glanceable message and stash the whole thing as detail.
  def humanize(reason) when is_binary(reason) do
    first = reason |> String.split("\n", parts: 2) |> hd() |> String.trim()
    detail = if String.contains?(reason, "\n"), do: reason, else: nil
    %AppError{message: first, detail: detail}
  end

  def humanize(reason) do
    text = inspect(reason)
    %AppError{message: text |> String.split("\n", parts: 2) |> hd(), detail: text}
  end
end
