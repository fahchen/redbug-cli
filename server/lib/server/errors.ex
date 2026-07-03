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
    unreachable: "Can't reach node — check address / cookie",
    no_ssh_host: "This node has no SSH host set",
    bad_container: "Invalid container name (letters, digits, . _ - only)",
    no_container: "No container / service name set for this SSH node",
    no_ip: "Could not read the container's IP over SSH",
    no_port: "Could not find the node's epmd port in the container",
    exec_timeout: "Timed out running discovery over SSH",
    ssh_auth: "SSH auth failed — no usable key (agent or ~/.ssh)"
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

  def humanize({:ssh_connect, reason}),
    do: %AppError{message: "SSH connect failed — check host, user, and key", detail: inspect(reason)}

  def humanize({:ssh_forward, reason}),
    do: %AppError{message: "SSH port-forward failed", detail: inspect(reason)}

  def humanize({:discovery_exit, _status}),
    do: %AppError{
      message: "Container not found on the host — check the container / service name",
      detail: nil
    }

  def humanize(reason) do
    text = inspect(reason)
    %AppError{message: text |> String.split("\n", parts: 2) |> hd(), detail: text}
  end
end
