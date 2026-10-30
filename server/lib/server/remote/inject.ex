defmodule Server.Remote.Inject do
  @moduledoc """
  Loads controller modules onto a target node, so the target can run them.

  The controller and the target can run different OTP versions. A beam that
  OTP 29 compiles does not load on OTP 27 (`{:error, :badfile}`). So the
  controller sends the abstract code (the `Dbgi` chunk) of the module, and the
  target compiles it with `:compile.noenv_forms/2` and loads the result.

  The compiled module carries the md5 of the controller's beam in the
  `redbug_cli_md5` attribute. A later call skips a module whose attribute
  matches, so the target compiles each module version one time. This also keeps
  a reload from purging the code of a process that still runs it.

  When the target cannot compile the module (the target has no `compiler`
  application, or the controller beam has no abstract code), the controller
  sends its own beam. That beam loads only on a target whose OTP can read it.

  `strip_beams` removes the `Dbgi` chunk in a release, so the `server` release
  copies the unstripped beams of `modules/0` back (see `mix.exs`).
  """

  @attr :redbug_cli_md5
  # noenv: ERL_COMPILER_OPTIONS of the target (warnings_as_errors, for example)
  # must not change how the target compiles the controller's code.
  @opts [:binary, :return_errors]

  @doc "All modules that the controller loads onto target nodes."
  @spec modules() :: [module()]
  def modules, do: [Server.Remote.Worker, :redbug_targ, :redbug_compiler]

  @doc "Loads each module of `mods` onto `target`, unless the current version is there."
  @spec ensure_loaded(node(), [module()]) :: :ok | {:error, term()}
  def ensure_loaded(target, mods) do
    Enum.reduce_while(mods, :ok, fn mod, :ok ->
      case ensure(target, mod) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp ensure(target, mod) do
    case :code.get_object_code(mod) do
      {^mod, beam, file} ->
        md5 = mod.module_info(:md5)
        if current?(target, mod, md5), do: :ok, else: load(target, mod, beam, file, md5)

      :error ->
        {:error, {:no_object_code, mod}}
    end
  end

  defp current?(target, mod, md5) do
    case :rpc.call(target, mod, :module_info, [:attributes]) do
      attrs when is_list(attrs) -> Keyword.get(attrs, @attr) == [md5]
      _ -> false
    end
  end

  defp load(target, mod, beam, file, md5) do
    case compile_on_target(target, beam, md5) do
      {:ok, ^mod, bin} -> load_binary(target, mod, file, bin)
      :use_beam -> load_binary(target, mod, file, beam)
      {:error, reason} -> {:error, {:compile, mod, reason}}
    end
  end

  defp compile_on_target(target, beam, md5) do
    case :beam_lib.chunks(beam, [:abstract_code]) do
      {:ok, {_mod, [abstract_code: {:raw_abstract_v1, forms}]}} ->
        case :rpc.call(target, :compile, :noenv_forms, [tag(forms, md5), @opts]) do
          {:ok, mod, bin} -> {:ok, mod, bin}
          {:badrpc, {:EXIT, {:undef, [{:compile, :noenv_forms, _, _} | _]}}} -> :use_beam
          other -> {:error, other}
        end

      _no_abstract_code ->
        :use_beam
    end
  end

  # Attributes must come before the functions, so add the md5 next to `-module`.
  defp tag([{:attribute, anno, :module, _} = module | rest], md5),
    do: [module, {:attribute, anno, @attr, md5} | rest]

  defp tag([form | rest], md5), do: [form | tag(rest, md5)]

  defp load_binary(target, mod, file, bin) do
    case :rpc.call(target, :code, :load_binary, [mod, file, bin]) do
      {:module, ^mod} -> :ok
      other -> {:error, {:load, mod, other}}
    end
  end
end
