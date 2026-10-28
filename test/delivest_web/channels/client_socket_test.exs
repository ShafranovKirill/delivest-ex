defmodule DelivestWeb.ClientSocketTest do
  use DelivestWeb.ChannelCase, async: true

  import Delivest.Factory
  import Delivest.OrderFixtures

  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Identity.{ClientAuth, PhoneConfirmations}
  alias Delivest.Integrations.Crm.BranchSettings
  alias Delivest.Integrations.Frontpad
  alias Delivest.Integrations.Frontpad.Webhook
  alias Delivest.Oms.Order.CrmSync
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

    {:ok, _} = Orders.advance_order(order, :ready, :system)

    assert_push "order", %{order: %{id: id, status: :ready}, active: true}, 1_000
    assert id == order.id
    refute_push "order", _

    {:ok, _} = Orders.advance_order(Repo.reload!(order), :completed, :system)
    assert_push "order", %{order: %{status: :completed}, active: false}, 1_000
  end

  test "pushes frontpad status changes of crm orders" do
    branch = insert(:branch)

    Repo.insert!(%BranchInfo{
      branch_id: branch.id,
      crm: %BranchSettings{
        enabled: true,
        provider: :frontpad,
        frontpad: %Frontpad.Settings{
          api_key: "key",
          webhook_token: "hook-#{branch.id}",
          statuses: %Frontpad.StatusCodes{preparing: "2", completed: "5"}
        }
      }
    })

    order =
      branch.id
      |> order_fixture(attrs: %{"session_id" => "crm-sess"})
      |> Ecto.Changeset.change(
        crm: %CrmSync{provider: "frontpad", external_id: "900", status: "sent"}
      )
      |> Repo.update!()

    {:ok, _reply, _socket} = "crm-sess" |> connect_as() |> subscribe_and_join("orders", %{})

    {:ok, _} = Webhook.change_status("hook-#{branch.id}", 900, 2, nil)
    assert_push "order", %{order: %{id: id, status: :preparing}, active: true}, 1_000
    assert id == order.id

    {:ok, _} = Webhook.change_status("hook-#{branch.id}", "900", "5", nil)
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

    {:ok, _} = Orders.advance_order(order, :preparing, :system)

    assert_push "order", %{order: %{status: :preparing}}, 1_000
  end

  test "auth channel signals the confirmation and leaves it for the http exchange" do
    {:ok, confirmation} =
      PhoneConfirmations.create(%{phone: @phone, session_id: "sess-a", call_id: "777"})

    assert {:error, %{code: "confirmation_not_found"}} =
             "sess-b" |> connect_as() |> subscribe_and_join("auth:#{confirmation.id}", %{})

    {:ok, _reply, _socket} =
      "sess-a" |> connect_as() |> subscribe_and_join("auth:#{confirmation.id}", %{})

    refute_push "confirmed", _

    assert :ok = ClientAuth.confirm_call("777", @phone)

    assert_push "confirmed", %{}, 1_000
    assert {:ok, @phone} = PhoneConfirmations.consume(confirmation.id, "sess-a")
  end
end
