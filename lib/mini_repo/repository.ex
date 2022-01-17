defmodule MiniRepo.Repository do
  @moduledoc false

  @derive {Inspect, only: [:name, :public_key, :store, :registry]}
  @enforce_keys [:name, :public_key, :private_key, :store]
  defstruct [:name, :public_key, :private_key, :store, registry: %{}]

  def new(name, options, stores) do
    %MiniRepo.Repository{
      name: name,
      private_key: options["private_key"],
      public_key: options["public_key"],
      store: stores[options["store"]]
    }
  end
end
