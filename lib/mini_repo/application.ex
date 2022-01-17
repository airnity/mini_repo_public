defmodule MiniRepo.Application do
  @moduledoc false

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    config = configure()

    stores = stores(config)
    repos = repositories(config, stores)
    regular_repos = for %MiniRepo.Repository{} = repo <- repos, do: repo.name

    secrets = configure_watched_secrets(repos)

    children =
      []
      |> add_secrets_watcher(config, secrets)
      |> add_task_supervisor()
      |> add_mini_repo(repos)
      |> add_cowboy(config, regular_repos)

    opts = [strategy: :one_for_one, name: MiniRepo.Supervisor]

    Supervisor.start_link(children, opts)
  end

  # -- Private

  defp stores(config) do
    for {name, options} <- Map.fetch!(config, :stores), into: %{} do
      mod = get_store_mod(options["type"])
      {name, {mod, bucket: options["bucket"], options: [region: options["region"]]}}
    end
  end

  defp get_store_mod("s3"), do: MiniRepo.Store.S3
  defp get_store_mod("local"), do: MiniRepo.Store.Local

  defp repositories(config, stores) do
    for {name, options} <- Map.fetch!(config, :repositories) do
      if Map.has_key?(options, "upstream_url") do
        Logger.info("Starting mirror #{name} with store #{inspect(options["store"])}")
        MiniRepo.Mirror.new(name, options, stores)
      else
        Logger.info("Starting repository #{name} with store #{inspect(options["store"])}")
        MiniRepo.Repository.new(name, options, stores)
      end
    end
  end

  defp configure_watched_secrets(repos) do
    repos_public_secrets =
      for %MiniRepo.Repository{} = repo <- repos do
        repo.public_key_secret_name
      end

    repos_private_secrets =
      for %MiniRepo.Repository{} = repo <- repos do
        repo.private_key_secret_name
      end

    ["auth_token"] ++ repos_public_secrets ++ repos_private_secrets
  end

  defp add_secrets_watcher(children, config, secrets) do
    child =
      {SecretsWatcher,
       [
         name: :secrets,
         secrets_watcher_config: [directory: config.secrets_directory, secrets: secrets]
       ]}

    children ++ [child]
  end

  defp add_task_supervisor(children) do
    children ++ [{Task.Supervisor, name: MiniRepo.TaskSupervisor}]
  end

  defp add_cowboy(children, config, regular_repos) do
    http_options = [
      port: config.port
    ]

    Logger.info("Starting HTTP server with options #{inspect(http_options)}")

    router_opts = [
      url: config.url,
      repositories: regular_repos
    ]

    endpoint_spec =
      Plug.Cowboy.child_spec(
        plug: {MiniRepo.Endpoint, router_opts},
        scheme: :http,
        options: http_options
      )

    children ++ [endpoint_spec]
  end

  defp add_mini_repo(children, repos) do
    repository_specs = Enum.map(repos, &repository_spec/1)

    children ++ repository_specs
  end

  defp repository_spec(%MiniRepo.Mirror{} = repo) do
    {MiniRepo.Mirror.Server, mirror: repo, name: String.to_atom(repo.name)}
  end

  defp repository_spec(%MiniRepo.Repository{} = repo) do
    {MiniRepo.Repository.Server, repository: repo, name: String.to_atom(repo.name)}
  end

  defp configure() do
    alias Vapor.Provider.{Dotenv, Env, File}

    env_provider = [
      %Dotenv{},
      %Env{bindings: [configuration_path: "MINI_REPO_CONFIG_PATH"]}
    ]

    env_config = Vapor.load!(env_provider)

    providers = [
      %File{
        path: env_config.configuration_path,
        bindings: [
          {:port, ["appConfig", "port"], map: &String.to_integer/1},
          {:url, ["appConfig", "url"]},
          {:secrets_directory, ["globalConfig", "secretsDirectory"]},
          {:repositories, ["appConfig", "repositories"]},
          {:stores, ["appConfig", "stores"]}
        ]
      }
    ]

    Vapor.load!(providers)
  end
end
