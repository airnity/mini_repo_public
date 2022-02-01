defmodule MiniRepo.AWS do
  @moduledoc false

  def get_caller_identity_arn() do
    {:ok, %{body: %{arn: arn}}} = ExAws.STS.get_caller_identity() |> ExAws.request()

    arn
  end
end
