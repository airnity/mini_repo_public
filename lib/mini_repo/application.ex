defmodule MiniRepo.Application do
  @moduledoc false

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    config = configure()

    configure_ex_aws(config)

    stores = stores(config)
    repos = repositories(config, stores)
    regular_repos = for %MiniRepo.Repository{} = repo <- repos, do: repo.name

    children =
      []
      |> add_secret_agent(config, repos)
      |> add_task_supervisor()
      |> add_mini_repo(repos)
      |> add_cowboy(config, regular_repos)

    opts = [strategy: :one_for_one, name: MiniRepo.Supervisor]

    Supervisor.start_link(children, opts)
  end

  # -- Private

  defp configure_ex_aws(config) do
    ex_aws_config =
      case config.aws_auth_type do
        "profile" ->
          profile = Map.get(config.aws_auth_options, "profile", "default")

          [
            access_key_id: [{:awscli, profile, 30}],
            secret_access_key: [{:awscli, profile, 30}]
          ]

        "session" ->
          [
            access_key_id: {:system, "AWS_ACCESS_KEY_ID"},
            security_token: {:system, "AWS_SESSION_TOKEN"},
            secret_access_key: {:system, "AWS_SECRET_ACCESS_KEY"}
          ]

        "irsa" ->
          [
            secret_access_key: [{:awscli, "dummy", 30}],
            access_key_id: [{:awscli, "dummy", 30}],
            awscli_auth_adapter: ExAws.STS.AuthCache.AssumeRoleWebIdentityAdapter
          ]

        method ->
          raise "Unsupported AWS authentication method #{method}"
      end

    Application.put_all_env([{:ex_aws, ex_aws_config}])
  end

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

  defp configure_watched_secrets(config, repos) do
    secrets_directory = config.secrets_directory

    secrets = %{
      "api_token" => [directory: secrets_directory],
      "repos_token" => [directory: secrets_directory]
    }

    repos_public_secrets =
      for %MiniRepo.Repository{} = repo <- repos, into: %{} do
        {repo.public_key_secret_name, [directory: secrets_directory]}
      end

    repos_private_secrets =
      for %MiniRepo.Repository{} = repo <- repos, into: %{} do
        {repo.private_key_secret_name, [directory: secrets_directory]}
      end

    secrets
    |> Map.merge(repos_public_secrets)
    |> Map.merge(repos_private_secrets)
  end

  defp add_secret_agent(children, config, repos) do
    secrets = configure_watched_secrets(config, repos)
    child = {SecretAgent, [name: :secrets, secret_agent_config: [secrets: secrets]]}

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
          {:aws_auth_type, ["appConfig", "aws_auth", "type"]},
          {:aws_auth_options, ["appConfig", "aws_auth", "options"], default: %{}},
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
