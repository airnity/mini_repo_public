defmodule MiniRepo.MixProject do
  use Mix.Project

  def project() do
    [
      app: :mini_repo,
      version: "0.2.0",
      elixir: "~> 1.13",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases()
    ]
  end

  def application() do
    [
      extra_applications: [:crypto, :inets, :ssl],
      mod: {MiniRepo.Application, []}
    ]
  end

  defp deps() do
    [
      {:hex_core, "~> 0.8"},
      {:secrets_watcher, "~> 0.6"},
      {:vapor, "~> 0.10"},

      # plug
      {:plug, "~> 1.0"},
      {:plug_cowboy, "~> 2.0"},

      # s3
      {:ex_aws, "~> 2.0"},
      {:ex_aws_s3, "~> 2.0"},
      {:hackney, "~> 1.9"},
      {:jason, "~> 1.0"},

      # dev
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.0", only: [:test, :dev], runtime: false},
      {:git_hooks, ">= 0.0.0", only: [:test, :dev], runtime: false},
      {:mix_audit, "~> 1.0", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases() do
    [
      test: ["test --no-start"]
    ]
  end
end
