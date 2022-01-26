import Config

if Mix.env() != :prod do
  config :git_hooks,
    auto_install: true,
    verbose: true,
    hooks: [
      pre_commit: [
        tasks: [
          {:cmd, "mix credo"},
          {:cmd, "mix format --check-formatted"}
        ]
      ],
      pre_push: [
        verbose: false,
        tasks: [
          {:cmd, "mix deps.unlock --check-unused"},
          {:cmd, "mix dialyzer"}
        ]
      ]
    ]
end

import_config "#{Mix.env()}.exs"
