defmodule MiniRepo.Endpoint do
  @moduledoc false

  use Plug.Builder

  plug Plug.Logger

  plug MiniRepo.APIAuth
  plug MiniRepo.APIRouter, builder_opts()
end
