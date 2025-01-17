defmodule MiniRepo.APIRouter do
  @moduledoc false
  use Plug.Router

  plug Plug.Parsers,
    parsers: [MiniRepo.HexErlangParser],
    pass: ["*/*"]

  plug :match
  plug :dispatch, builder_opts()

  def call(conn, opts) do
    conn =
      Plug.Conn.put_private(conn, :mini_repo, %{
        url: opts[:url],
        repositories: opts[:repositories]
      })

    super(conn, opts)
  end

  post "/api/repos/:repo/publish" do
    {:ok, tarball, conn} = read_tarball(conn)
    repo = repo!(conn, repo)

    case MiniRepo.Repository.Server.publish(repo, tarball) do
      :ok ->
        body = %{"url" => opts[:url]}
        body = :erlang.term_to_binary(body)

        conn
        |> put_resp_content_type("application/vnd.hex+erlang")
        |> send_resp(200, body)

      {:error, _} = error ->
        body = :erlang.term_to_binary(error)

        conn
        |> put_resp_content_type("application/vnd.hex+erlang")
        |> send_resp(400, body)
    end
  end

  delete "/api/repos/:repo/packages/:name/releases/:version" do
    repo = repo!(conn, repo)
    MiniRepo.Repository.Server.revert(repo, name, version)

    send_resp(conn, 204, "")
  end

  post "/api/repos/:repo/packages/:name/releases/:version/retire" do
    repo = repo!(conn, repo)
    MiniRepo.Repository.Server.retire(repo, name, version, conn.body_params)

    send_resp(conn, 201, "")
  end

  delete "/api/repos/:repo/packages/:name/releases/:version/retire" do
    repo = repo!(conn, repo)
    MiniRepo.Repository.Server.unretire(repo, name, version)

    send_resp(conn, 201, "")
  end

  post "/api/repos/:repo/packages/:name/releases/:version/docs" do
    repo = repo!(conn, repo)
    {:ok, docs_tarball, conn} = read_tarball(conn)
    MiniRepo.Repository.Server.publish_docs(repo, name, version, docs_tarball)

    send_resp(conn, 201, "")
  end

  get "/repos/:repo/packages/:package_name/" do
    repo = repo!(conn, repo)
    package = MiniRepo.Repository.Server.fetch_package(repo, package_name)

    send_resp(conn, 200, package)
  end

  get "/repos/:repo/tarballs/:tarball_name" do
    repo = repo!(conn, repo)
    tarball = MiniRepo.Repository.Server.fetch_tarball(repo, tarball_name)

    send_resp(conn, 200, tarball)
  end

  match _ do
    send_resp(conn, 404, "not found")
  end

  defp repo!(conn, repo) do
    allowed_repos = conn.private.mini_repo.repositories

    if repo in allowed_repos do
      String.to_existing_atom(repo)
    else
      raise ArgumentError,
            "#{inspect(repo)} is not allowed, allowed repos: #{inspect(allowed_repos)}"
    end
  end

  defp read_tarball(conn, tarball \\ <<>>) do
    case Plug.Conn.read_body(conn) do
      {:more, partial, conn} ->
        read_tarball(conn, tarball <> partial)

      {:ok, body, conn} ->
        {:ok, tarball <> body, conn}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
