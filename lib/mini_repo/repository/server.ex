defmodule MiniRepo.Repository.Server do
  @moduledoc false

  use Agent
  alias MiniRepo.RegistryBackup

  def start_link(options) do
    {repository, options} = Keyword.pop(options, :repository)
    Agent.start_link(fn -> RegistryBackup.load(repository) end, options)
  end

  def fetch_package(pid, package_name) do
    Agent.get(pid, fn repository ->
      {:ok, package} =
        MiniRepo.Store.fetch(repository.store, package_path(repository, package_name))

      package
    end)
  end

  def fetch_tarball(pid, tarball_name) do
    Agent.get(pid, fn repository ->
      {:ok, tarball} =
        MiniRepo.Store.fetch(repository.store, tarball_path(repository, tarball_name))

      tarball
    end)
  end

  def publish(pid, tarball) do
    with {:ok, {package_name, release}} <- MiniRepo.Utils.unpack_tarball(tarball) do
      Agent.update(pid, fn repository ->
        :ok =
          store_put(repository, tarball_path(repository, package_name, release.version), tarball)

        update_registry(repository, package_name, fn registry ->
          Map.update(registry, package_name, [release], fn releases ->
            Enum.sort([release | releases], &(Version.compare(&1.version, &2.version) == :lt))
          end)
        end)
      end)
    end
  end

  def revert(pid, package_name, version) do
    Agent.update(pid, fn repository ->
      update_registry(repository, package_name, fn registry ->
        case Map.fetch!(registry, package_name) do
          [%{version: ^version}] ->
            :ok = store_delete(repository, tarball_path(repository, package_name, version))
            Map.delete(registry, package_name)

          _ ->
            Map.update!(registry, package_name, fn releases ->
              Enum.reject(releases, &(&1.version == version))
            end)
        end
      end)
    end)
  end

  def retire(pid, package_name, version, params) do
    Agent.update(pid, fn repository ->
      update_registry(repository, package_name, fn registry ->
        Map.update!(registry, package_name, fn releases ->
          for release <- releases do
            if release.version == version do
              retired = %{
                reason: params |> Map.fetch!("reason") |> retirement_reason(),
                message: Map.fetch!(params, "message")
              }

              Map.put(release, :retired, retired)
            else
              release
            end
          end
        end)
      end)
    end)
  end

  def unretire(pid, package_name, version) do
    Agent.update(pid, fn repository ->
      update_registry(repository, package_name, fn registry ->
        Map.update!(registry, package_name, fn releases ->
          for release <- releases do
            if release.version == version do
              Map.delete(release, :retired)
            else
              release
            end
          end
        end)
      end)
    end)
  end

  def publish_docs(pid, package_name, version, docs_tarball) do
    Agent.update(pid, fn repository ->
      store_put(
        repository,
        ["repos", repository.name, "docs", "#{package_name}-#{version}.tar.gz"],
        docs_tarball
      )

      repository
    end)
  end

  def rebuild(pid) do
    Agent.update(pid, fn repository ->
      build_full_registry(repository)
      repository
    end)
  end

  # -- Private

  defp tarball_path(repository, package_name, version) do
    ["repos", repository.name, "tarballs", "#{package_name}-#{version}.tar"]
  end

  defp tarball_path(repository, tarball_name) do
    ["repos", repository.name, "tarballs", tarball_name]
  end

  defp package_path(repository, package_name) do
    ["repos", repository.name, "packages", package_name]
  end

  defp retirement_reason("other"), do: :RETIRED_OTHER
  defp retirement_reason("invalid"), do: :RETIRED_INVALID
  defp retirement_reason("security"), do: :RETIRED_SECURITY
  defp retirement_reason("deprecated"), do: :RETIRED_DEPRECATED
  defp retirement_reason("renamed"), do: :RETIRED_RENAMED

  defp update_registry(repository, package_name, fun) do
    repository = Map.update!(repository, :registry, fun)
    build_partial_registry(repository, package_name)
    RegistryBackup.save(repository)
    repository
  end

  defp build_full_registry(repository) do
    resources = MiniRepo.RegistryBuilder.build_full(repository, repository.registry)

    for {name, content} <- resources do
      store_put(repository, ["repos", repository.name, name], content)
    end
  end

  defp build_partial_registry(repository, package_name) do
    resources =
      MiniRepo.RegistryBuilder.build_partial(repository, repository.registry, package_name)

    for {name, content} <- resources do
      store_put(repository, ["repos", repository.name, name], content)
    end
  end

  defp store_put(repository, name, content) do
    options = []
    :ok = MiniRepo.Store.put(repository.store, name, content, options)
  end

  defp store_delete(repository, name) do
    MiniRepo.Store.delete(repository.store, name)
  end
end
