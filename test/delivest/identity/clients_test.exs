defmodule Delivest.Identity.ClientsTest do
  use Delivest.DataCase, async: true

  import Delivest.Factory

  alias Delivest.Identity
  alias Delivest.Identity.Client

  defp staff_with_permissions(permissions) do
    role = insert(:role, permissions: permissions)
    insert(:staff, role: role)
  end

  describe "list_clients/2" do
    test "returns only non-deleted clients for users with clients.read permission" do
      staff = staff_with_permissions(["clients.read"])
      active = insert(:client, phone: "+79990000001", name: "Alice", status: :active)

      deleted =
        insert(:client,
          phone: "+79990000002",
          name: "Deleted",
          status: :active,
          deleted_at: DateTime.utc_now(:second)
        )

      _other = insert(:client, phone: "+79990000003", name: "Bob", status: :guest)

      assert {:ok, {clients, _meta}} = Identity.list_clients(staff, %{})
      ids = Enum.map(clients, & &1.id)
      assert active.id in ids
      refute deleted.id in ids
    end

    test "returns {:error, :forbidden} without read permission" do
      staff = staff_with_permissions([])

      assert {:error, :forbidden} = Identity.list_clients(staff, %{})
    end
  end

  describe "get_client/2" do
    test "returns {:ok, client} when client exists and is active" do
      staff = staff_with_permissions(["clients.read"])
      client = insert(:client, phone: "+79990000010", name: "Anna")

      assert {:ok, %Client{} = fetched} = Identity.get_client(staff, client.id)
      assert fetched.id == client.id
    end

    test "returns {:error, :not_found} for unknown client" do
      staff = staff_with_permissions(["clients.read"])

      assert {:error, :not_found} = Identity.get_client(staff, Ecto.UUID.generate())
    end

    test "returns {:error, :forbidden} without read permission" do
      staff = staff_with_permissions([])
      client = insert(:client, phone: "+79990000011", name: "No Access")

      assert {:error, :forbidden} = Identity.get_client(staff, client.id)
    end
  end

  describe "get_or_create_client_by_phone/2" do
    test "updates existing client without changing phone when found" do
      existing = insert(:client, phone: "+79990000020", name: "Old Name")

      assert {:ok, %Client{} = client} =
               Identity.get_or_create_client_by_phone(existing.phone, %{"name" => "New Name"})

      assert client.id == existing.id
      assert client.name == "New Name"
    end

    test "creates new client when phone is not found" do
      attrs = %{name: "New Client"}

      assert {:ok, %Client{} = client} =
               Identity.get_or_create_client_by_phone("+79990000021", attrs)

      assert client.phone == "+79990000021"
      assert client.name == "New Client"
    end
  end

  describe "create_client/1" do
    test "creates a client with valid attributes" do
      assert {:ok, %Client{} = client} =
               Identity.create_client(%{
                 "phone" => "+79990000030",
                 "name" => "Client A",
                 "status" => :active
               })

      assert client.phone == "+79990000030"
      assert client.status == :active
    end

    test "returns validation errors for invalid phone" do
      assert {:error, changeset} =
               Identity.create_client(%{"phone" => "12345", "status" => :guest})

      assert "The number must be in the format +7XXXXXXXXXX" in errors_on(changeset).phone
    end
  end

  describe "update_client/3" do
    test "updates a client when permitted" do
      staff = staff_with_permissions(["clients.update"])
      client = insert(:client, phone: "+79990000040", name: "Old")

      assert {:ok, %Client{} = updated} =
               Identity.update_client(staff, client, %{"name" => "Updated", "status" => "active"})

      assert updated.name == "Updated"
      assert updated.status == :active
    end

    test "returns {:error, :forbidden} when staff lacks permission" do
      staff = staff_with_permissions([])
      client = insert(:client, phone: "+79990000041", name: "Keep")

      assert {:error, :forbidden} = Identity.update_client(staff, client, %{"name" => "Nope"})
    end
  end

  describe "soft_delete_client/2" do
    test "marks client as deleted when permitted" do
      staff = staff_with_permissions(["clients.delete"])
      client = insert(:client, phone: "+79990000050", name: "Delete Me")

      assert {:ok, %Client{} = deleted} = Identity.soft_delete_client(staff, client)
      assert deleted.deleted_at != nil
    end

    test "returns {:error, :forbidden} when staff lacks permission" do
      staff = staff_with_permissions([])
      client = insert(:client, phone: "+79990000051", name: "Keep Me")

      assert {:error, :forbidden} = Identity.soft_delete_client(staff, client)
    end
  end

  describe "get_clients_map/1" do
    test "returns a map keyed by id for active clients" do
      client1 = insert(:client, phone: "+79990000060", name: "First")
      client2 = insert(:client, phone: "+79990000061", name: "Second")

      deleted =
        insert(:client,
          phone: "+79990000062",
          name: "Deleted",
          deleted_at: DateTime.utc_now(:second)
        )

      result = Identity.get_clients_map([client1.id, client2.id, deleted.id])

      assert MapSet.new(Map.keys(result)) == MapSet.new([client1.id, client2.id])
      assert result[client1.id].name == "First"
    end
  end

  describe "search_clients/3" do
    test "returns matching clients by name or phone for authorized staff" do
      staff = staff_with_permissions(["clients.read"])
      insert(:client, phone: "+79990000070", name: "Ada Lovelace")
      insert(:client, phone: "+79990000071", name: "Grace Hopper")

      assert [%Client{} | _] = Identity.search_clients(staff, "Ada", 10)
      assert [%Client{} | _] = Identity.search_clients(staff, "+79990000071", 10)
    end

    test "returns {:error, :forbidden} without read permission" do
      staff = staff_with_permissions([])

      assert {:error, :forbidden} = Identity.search_clients(staff, "John", 10)
    end
  end

  describe "get_client_ids_by_search/1" do
    test "returns client ids matching query" do
      client = insert(:client, phone: "+79990000080", name: "Alpha")
      insert(:client, phone: "+79990000081", name: "Beta")

      assert client.id in Identity.get_client_ids_by_search("Alpha")
    end
  end
end
