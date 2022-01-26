defmodule MiniRepo.RepositoryTest do
  use ExUnit.Case, async: true
  alias MiniRepo.Repository

  @moduletag :to_fix

  test "inspect" do
    {private_key, public_key} = MiniRepo.Utils.generate_keys()

    repository = %Repository{
      name: "test",
      private_key_secret_name: private_key,
      public_key_secret_name: public_key,
      store: SomeStore
    }

    assert inspect(repository) ==
             "#MiniRepo.Repository<name: \"test\", public_key: #{inspect(public_key)}, registry: %{}, store: SomeStore, ...>"
  end
end
