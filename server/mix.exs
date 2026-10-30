defmodule Server.MixProject do
  use Mix.Project

  def project do
    [
      app: :server,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      compilers: Mix.compilers() ++ [:musubi_ts],
      releases: releases(),
      deps: deps()
    ]
  end

  defp releases do
    [
      server: [
        include_executables_for: [:unix],
        include_erts: true,
        strip_beams: true,
        steps: [:assemble, &keep_injected_debug_info/1]
      ]
    ]
  end

  # strip_beams removes the Dbgi chunk, but Server.Remote.Inject sends that
  # abstract code to the target, which compiles it for its own OTP version. Copy
  # the unstripped beams of the injected modules back into the release. (To keep
  # Dbgi in every beam grows the release from 33 MB to 50 MB.)
  defp keep_injected_debug_info(release) do
    for mod <- Server.Remote.Inject.modules() do
      source = :code.which(mod) |> List.to_string()
      pattern = Path.join([release.path, "lib", "*", "ebin", Path.basename(source)])
      [target] = Path.wildcard(pattern)
      File.cp!(source, target)
    end

    release
  end

  def application do
    [
      extra_applications: [:logger, :syntax_tools, :ssh],
      mod: {Server.Application, []}
    ]
  end

  defp deps do
    [
      {:musubi, "~> 0.13.0"},
      {:redbug, "~> 2.0"},
      {:phoenix, "~> 1.8"},
      {:phoenix_pubsub, "~> 2.1"},
      {:bandit, "~> 1.0"},
      {:jason, "~> 1.4"},
      {:nimble_parsec, "~> 1.4"}
    ]
  end
end
