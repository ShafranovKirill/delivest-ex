defmodule Delivest.Identity.ClientAddressesTest do
  use Delivest.DataCase, async: true

  import Delivest.Factory

  alias Delivest.Identity

  test "the same flat is remembered once with the latest details" do
    client = insert(:client)
    flat = %{street: "ул Ленина", house: "1", apartment: "5"}

    {:ok, first} = Identity.remember_client_address(client.id, Map.put(flat, :comment, "домофон"))

    {:ok, second} =
      Identity.remember_client_address(
        client.id,
        Map.merge(flat, %{comment: "со двора", latitude: 57.1, longitude: 65.5})
      )

    assert first.id == second.id

    assert [%{comment: "со двора", latitude: 57.1}] = Identity.list_client_addresses(client.id)

    {:ok, other} = Identity.remember_client_address(client.id, %{flat | apartment: "6"})
    refute other.id == first.id
  end
end
