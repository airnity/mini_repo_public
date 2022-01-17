defmodule MiniRepo.Repository do
  @moduledoc false

  @derive {Inspect, only: [:name, :public_key_secret_name, :store, :registry]}
  @enforce_keys [:name, :public_key_secret_name, :private_key_secret_name, :store]
  defstruct [:name, :public_key_secret_name, :private_key_secret_name, :store, registry: %{}]

  def new(name, options, stores) do
    %MiniRepo.Repository{
      name: name,
      private_key_secret_name: options["private_key_secret_name"],
      public_key_secret_name: options["public_key_secret_name"],
      store: stores[options["store"]]
    }
  end
end
