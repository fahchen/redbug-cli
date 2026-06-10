defmodule Server.Trace.Pattern do
  @moduledoc """
  Translate an Elixir-style trace pattern into the Erlang form `:redbug` expects.

  `:redbug` is Erlang-native: an Elixir module `Demo` is really the atom
  `'Elixir.Demo'`, and Erlang separates module from function with `:`, not `.`.
  So `Demo.add/2 -> return` must reach redbug as `'Elixir.Demo':add/2 -> return`.

  Only the leading MFA head is rewritten; args, guards (`when ...`) and actions
  (`-> return/stack`) pass through untouched. Erlang-style heads (lowercase atom
  module, or already-quoted `'Elixir.Demo':fun`) are left as-is, so both notations
  keep working.
  """

  @doc "Rewrite the module/function head of an Elixir-style pattern to redbug form."
  @spec to_redbug(String.t()) :: String.t()
  def to_redbug(text) when is_binary(text) do
    trimmed = String.trim_leading(text)

    cond do
      # Elixir module path: one or more `Uppercase` segments, optional `.function`.
      match = Regex.run(~r/^([A-Z]\w*(?:\.[A-Z]\w*)*)(\.[a-z_]\w*[?!]?)?(.*)$/s, trimmed) ->
        [_, mod_path, fun_part, rest] = match
        head = "'Elixir.#{mod_path}'" <> elixir_dot_to_colon(fun_part)
        head <> rest

      # Elixir erlang-module notation `:lists.reverse/1` -> `lists:reverse/1`.
      match = Regex.run(~r/^:([a-z_]\w*)(\.[a-z_]\w*[?!]?)?(.*)$/s, trimmed) ->
        [_, mod, fun_part, rest] = match
        mod <> elixir_dot_to_colon(fun_part) <> rest

      true ->
        trimmed
    end
  end

  defp elixir_dot_to_colon(""), do: ""
  defp elixir_dot_to_colon("." <> fun), do: ":" <> fun
end
