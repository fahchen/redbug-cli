defmodule Server.Trace.Pattern do
  @moduledoc """
  Translate an Elixir-style trace pattern into the Erlang form `:redbug` expects.

  `:redbug` is Erlang-native: an Elixir module `Demo` is really the atom
  `'Elixir.Demo'`, and Erlang separates module from function with `:`, not `.`.
  So `Demo.add/2 -> return` must reach redbug as `'Elixir.Demo':add/2 -> return`.

  Only the leading MFA head is parsed and rewritten; args, guards (`when ...`) and
  actions (`-> return/stack`) ride along as the unparsed remainder. Erlang-style
  heads (lowercase atom module, or already-quoted `'Elixir.Demo':fun`) match no
  rule, so they pass through untouched and both notations keep working.
  """

  import NimbleParsec

  word = ascii_string([?a..?z, ?A..?Z, ?0..?9, ?_], min: 0)

  upper_seg =
    ascii_string([?A..?Z], 1)
    |> concat(word)
    |> reduce({Enum, :join, [""]})

  lower_name =
    ascii_string([?a..?z, ?_], 1)
    |> concat(word)
    |> optional(ascii_string([??, ?!], min: 1))
    |> reduce({Enum, :join, [""]})

  # `Foo`, `Foo.Bar`, `Foo.Bar.baz` — uppercase module segments, optional
  # lowercase function tail. Segments stay distinguishable by leading case.
  elixir_head =
    upper_seg
    |> repeat(ignore(string(".")) |> concat(upper_seg))
    |> optional(ignore(string(".")) |> concat(lower_name))
    |> post_traverse({:build_elixir, []})

  # `:lists`, `:lists.reverse` — Elixir's erlang-module notation.
  erlang_head =
    ignore(string(":"))
    |> concat(lower_name)
    |> optional(ignore(string(".")) |> concat(lower_name))
    |> post_traverse({:build_erlang, []})

  defparsecp(:head, choice([elixir_head, erlang_head]))

  @doc "Rewrite the module/function head of an Elixir-style pattern to redbug form."
  @spec to_redbug(String.t()) :: String.t()
  def to_redbug(text) when is_binary(text) do
    trimmed = String.trim_leading(text)

    case head(trimmed) do
      {:ok, [head], rest, _ctx, _line, _offset} -> head <> rest
      _ -> trimmed
    end
  end

  defp build_elixir(rest, acc, context, _line, _offset) do
    segs = Enum.reverse(acc)

    {mods, fun} =
      case List.last(segs) do
        <<c, _::binary>> = last when c in ?a..?z or c == ?_ -> {Enum.drop(segs, -1), last}
        _ -> {segs, nil}
      end

    mod = "'Elixir." <> Enum.join(mods, ".") <> "'"
    head = if fun, do: mod <> ":" <> fun, else: mod
    {rest, [head], context}
  end

  defp build_erlang(rest, acc, context, _line, _offset) do
    head =
      case Enum.reverse(acc) do
        [mod] -> mod
        [mod, fun] -> mod <> ":" <> fun
      end

    {rest, [head], context}
  end
end
