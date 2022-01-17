defmodule MiniRepo.APIAuth do
  @moduledoc false

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_req_header(conn, "authorization") do
      [token] ->
        {:ok, auth_token} = SecretsWatcher.get_wrapped_secret(:secrets, "auth_token")

        if Plug.Crypto.secure_compare(token, auth_token.()) do
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
end
