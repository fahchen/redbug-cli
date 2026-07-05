defmodule Server.Remote.Worker do
  @moduledoc """
  The body of one Console execution. Runs **on the target node** — the
  controller loads this module's BEAM onto the target via
  `:code.load_binary/3` (see `Server.Remote.Console`) before spawning it, the
  same code-injection trick `:redbug` uses, so the target needs nothing
  pre-installed.

  The process is spawned with `Node.spawn/4` and monitored from the controller,
  which is what makes an execution force-stoppable: `Process.exit(pid, :kill)`
  propagates over distribution and tears this process down mid-eval.

  Eval auto-detects language: Elixir first (`Code.eval_string/1`), falling back
  to Erlang (`:erl_scan` → `:erl_parse` → `:erl_eval`) when the Elixir runtime
  isn't present on the target. stdout is captured by swapping the group leader
  for a tiny in-process IO collector, so it works without any Elixir stdlib.
  """

  @doc """
  Evaluate `code`, capturing return value + stdout, and reply to `reply_to`
  with `{:console_result, exec_id, {:ok | :error, result_string}, output}`.
  """
  def run(reply_to, exec_id, code) do
    collector = spawn(fn -> collect(reply_to, exec_id, []) end)
    prev_gl = Process.group_leader()
    Process.group_leader(self(), collector)

    result =
      try do
        eval(code)
      catch
        kind, reason -> {:error, fmt("~p", [{kind, reason}])}
      end

    Process.group_leader(self(), prev_gl)
    output = drain(collector)
    send(reply_to, {:console_result, exec_id, result, output})
  end

  # Elixir path first. Parse-time failures (Erlang syntax won't tokenize as
  # Elixir) and a missing Elixir runtime (UndefinedFunctionError) fall back to
  # the Erlang evaluator; genuine Elixir runtime errors are reported as-is.
  defp eval(code) do
    try do
      {value, _binding} = Code.eval_string(code)
      {:ok, inspect(value)}
    rescue
      e in [SyntaxError, TokenMissingError, UndefinedFunctionError] ->
        case erl_eval(code) do
          {:ok, _} = ok -> ok
          {:error, _} -> {:error, Exception.format(:error, e, [])}
        end

      e ->
        {:error, Exception.format(:error, e, [])}
    catch
      kind, reason -> {:error, Exception.format(kind, reason, [])}
    end
  end

  defp erl_eval(code) do
    charlist = :erlang.binary_to_list(ensure_dot(code))

    with {:ok, tokens, _} <- :erl_scan.string(charlist),
         {:ok, exprs} <- :erl_parse.parse_exprs(tokens) do
      try do
        {:value, value, _bindings} = :erl_eval.exprs(exprs, [])
        {:ok, fmt("~p", [value])}
      catch
        kind, reason -> {:error, fmt("~p", [{kind, reason}])}
      end
    else
      {:error, info, _} -> {:error, fmt("~p", [info])}
      other -> {:error, fmt("~p", [other])}
    end
  end

  # Erlang expr sequences must terminate with a period.
  defp ensure_dot(code) do
    trimmed = String.trim_trailing(code)
    if String.ends_with?(trimmed, "."), do: trimmed, else: trimmed <> "."
  end

  defp fmt(format, args), do: :erlang.iolist_to_binary(:io_lib.format(format, args))

  # Minimal IO server: accumulate put_chars AND stream each chunk back to the
  # controller (`{:console_chunk, ...}`) so stdout shows up live, not only at the
  # end. Still keeps the full buffer to hand back on :drain (authoritative final).
  defp collect(reply_to, exec_id, acc) do
    receive do
      {:io_request, from, ref, {:put_chars, _enc, chars}} ->
        send(from, {:io_reply, ref, :ok})
        emit(reply_to, exec_id, chars)
        collect(reply_to, exec_id, [acc, chars])

      {:io_request, from, ref, {:put_chars, _enc, m, f, a}} ->
        send(from, {:io_reply, ref, :ok})
        chars = apply(m, f, a)
        emit(reply_to, exec_id, chars)
        collect(reply_to, exec_id, [acc, chars])

      {:io_request, from, ref, _other} ->
        send(from, {:io_reply, ref, :ok})
        collect(reply_to, exec_id, acc)

      {:drain, from} ->
        send(from, {:drained, :erlang.iolist_to_binary(acc)})
    end
  end

  defp emit(reply_to, exec_id, chars) do
    send(reply_to, {:console_chunk, exec_id, :erlang.iolist_to_binary(chars)})
  end

  defp drain(collector) do
    send(collector, {:drain, self()})

    receive do
      {:drained, output} -> output
    after
      1000 -> ""
    end
  end
end
