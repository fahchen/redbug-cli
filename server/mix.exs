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
        strip_beams: true
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :syntax_tools],
      mod: {Server.Application, []}
    ]
  end

  defp deps do
    [
      {:musubi, "~> 0.12.0"},
      {:redbug, "~> 2.0"},
      {:phoenix, "~> 1.8"},
      {:phoenix_pubsub, "~> 2.1"},
      {:bandit, "~> 1.0"},
      {:jason, "~> 1.4"},
      {:nimble_parsec, "~> 1.4"}
    ]
  end
end
