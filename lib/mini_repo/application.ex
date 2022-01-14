defmodule MiniRepo.Application do
  @moduledoc false

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    config = Application.get_all_env(:mini_repo)

    repos = repositories(config)
    regular_repos = for %MiniRepo.Repository{} = repo <- repos, do: repo.name

    children =
      []
      |> add_task_supervisor()
      |> add_mini_repo(repos)
      |> add_cowboy(config, regular_repos)

    opts = [
      strategy: :one_for_one,
      name: MiniRepo.Supervisor
    ]

    Supervisor.start_link(children, opts)
  end

  # -- Private

  defp repositories(config) do
    for {name, options} <- Keyword.fetch!(config, :repositories) do
      if options[:upstream_url] do
        Logger.info("Starting mirror #{name} with store #{inspect(options[:store])}")
        struct!(MiniRepo.Mirror, [name: to_string(name)] ++ options)
      else
        Logger.info("Starting repository #{name} with store #{inspect(options[:store])}")
        struct!(MiniRepo.Repository, [name: to_string(name)] ++ options)
      end
    end
  end

  defp add_task_supervisor(children) do
    children ++ [{Task.Supervisor, name: MiniRepo.TaskSupervisor}]
  end

  defp add_cowboy(children, config, regular_repos) do
    http_options = [
      port: Keyword.fetch!(config, :port)
    ]

    Logger.info("Starting HTTP server with options #{inspect(http_options)}")

    router_opts = [
      url: config[:url],
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
end
