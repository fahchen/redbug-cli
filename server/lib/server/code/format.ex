defmodule Server.Code.Format do
  @moduledoc """
  Best-effort source formatting for Console code and Snippet bodies.

  Runs controller-side and is pure (no eval, no side-effects): only the
  language formatters touch the text. Language is auto-detected — Elixir is
  tried first via `Code.format_string!/2`; if it won't parse as Elixir the
  text is treated as Erlang (`:erl_scan` → `:erl_parse` → `:erl_prettypr`).
  Anything that fails both is returned verbatim, so formatting never blocks a
  save or a run.
  """

  # erl_prettypr ships in OTP's syntax_tools; xref can't see it at compile time.
  @compile {:no_warn_undefined, {:erl_prettypr, :format, 1}}

  @doc "Format `code`, auto-detecting Elixir vs Erlang. Returns raw on failure."
  @spec run(String.t()) :: String.t()
  def run(code) when is_binary(code) do
    case format_elixir(code) do
      {:ok, formatted} -> formatted
      :error -> format_erlang(code)
    end
  end

  defp format_elixir(code) do
    {:ok, code |> Code.format_string!([]) |> IO.iodata_to_binary()}
  rescue
    _ -> :error
  end

  defp format_erlang(code) do
    charlist = String.to_charlist(code)

    with {:ok, tokens, _} <- :erl_scan.string(charlist),
         {:ok, exprs} <- :erl_parse.parse_exprs(tokens) do
      Enum.map_join(exprs, "\n", &(&1 |> :erl_prettypr.format() |> to_string()))
    else
      _ -> code
    end
  rescue
    _ -> code
  end
end
