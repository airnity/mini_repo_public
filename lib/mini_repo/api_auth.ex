defmodule MiniRepo.APIAuth do
  @moduledoc false

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    route_token = get_wrapped_secret_for_route(conn)

    case get_req_header(conn, "authorization") do
      [token] ->
        if Plug.Crypto.secure_compare(token, route_token.()) do
          conn
        else
          unauthorized(conn)
        end

      _ ->
        unauthorized(conn)
    end
  end

  defp unauthorized(conn) do
    conn
    |> put_resp_content_type("application/vnd.hex+erlang")
    |> send_resp(401, :erlang.term_to_binary("unauthorized"))
    |> halt()
  end

  defp get_wrapped_secret_for_route(conn) do
    token_name =
      case conn do
        %{path_info: ["api" | _rest]} -> "api_token"
        %{path_info: ["repos" | _rest]} -> "repos_token"
      end

    {:ok, token} = SecretAgent.get_secret(:secrets, token_name, erase: false)

    token
  end
end
