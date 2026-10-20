defmodule DelivestWeb.ClientSocketTest do
  use DelivestWeb.ChannelCase, async: true

  import Delivest.Factory
  import Delivest.OrderFixtures

  alias Delivest.Identity.{ClientAuth, PhoneConfirmations}
  alias Delivest.Oms.Orders
  alias Delivest.Repo
  alias DelivestWeb.{ClientSocket, ClientToken}

  @branch_id "00000000-0000-4000-8000-0000000000d1"
  @phone "+79991234567"

  defp connect_as(session_id, client_id \\ nil) do
    {:ok, socket} =
      connect(ClientSocket, %{"token" => ClientToken.issue_socket(session_id, client_id)})

    socket
  end

  test "rejects connections without a valid token" do
    assert :error = connect(ClientSocket, %{})
    assert :error = connect(ClientSocket, %{"token" => "forged"})
  end

  test "pushes status changes of the session's orders" do
    order = order_fixture(@branch_id, attrs: %{"session_id" => "sess-1"})
    {:ok, _reply, _socket} = "sess-1" |> connect_as() |> subscribe_and_join("orders", %{})
    {:ok, _reply, _other} = "sess-2" |> connect_as() |> subscribe_and_join("orders", %{})

    {:ok, _} = Orders.update_order_details(order, %{"status" => "ready"})

    assert_push "order", %{order: %{id: id, status: :ready}, active: true}, 1_000
    assert id == order.id
    refute_push "order", _

    {:ok, _} = Orders.update_order_details(Repo.reload!(order), %{"status" => "completed"})
    assert_push "order", %{order: %{status: :completed}, active: false}, 1_000
  end

  test "pushes orders of the signed in client from any session" do
    client = insert(:client)

    order =
      @branch_id
      |> order_fixture(attrs: %{"session_id" => "phone"})
      |> Ecto.Changeset.change(client_id: client.id)
      |> Repo.update!()

    {:ok, _reply, _socket} =
      "laptop" |> connect_as(client.id) |> subscribe_and_join("orders", %{})

    {:ok, _} = Orders.update_order_details(order, %{"status" => "preparing"})

    assert_push "order", %{order: %{status: :preparing}}, 1_000
  end

  test "auth channel sends tokens once the call is confirmed" do
    {:ok, confirmation} =
      PhoneConfirmations.create(%{phone: @phone, session_id: "sess-a", call_id: "777"})

    assert {:error, %{code: "confirmation_not_found"}} =
             "sess-b" |> connect_as() |> subscribe_and_join("auth:#{confirmation.id}", %{})

    {:ok, _reply, _socket} =
      "sess-a" |> connect_as() |> subscribe_and_join("auth:#{confirmation.id}", %{})

    refute_push "confirmed", _

    assert :ok = ClientAuth.confirm_call("777", @phone)

    assert_push "confirmed",
                %{status: "confirmed", access_token: token, client: %{phone: @phone}},
                1_000

    assert {:ok, _client_id} = ClientToken.verify_access(token)
  end
end
