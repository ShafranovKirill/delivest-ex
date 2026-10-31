defmodule Delivest.Oms.OrderLockTest do
  use Delivest.DataCase, async: true

  import Delivest.Factory
  import Delivest.OrderFixtures

  alias Delivest.Oms.{Order, OrderLock, Orders}
  alias Delivest.Payments
  alias Delivest.Payments.Payment

  @branch_id "00000000-0000-4000-8000-000000000002"

  defp with_status(order, status),
    do: order |> Ecto.Changeset.change(status: status) |> Repo.update!()

  defp admin, do: insert(:staff, role: build(:role, permissions: ["admin"]))

  test "a new order can change everything" do
    order = order_fixture(@branch_id)
    assert OrderLock.allowed(order) == OrderLock.changes()
  end

  test "finished orders change nothing" do
    order = @branch_id |> order_fixture() |> with_status(:completed)
    assert {:error, :order_finished} = OrderLock.editable(order)
    assert OrderLock.allowed(order) == []
  end

  test "a ready order keeps its time" do
    order = @branch_id |> order_fixture() |> with_status(:ready)
    assert {:error, :order_ready} = OrderLock.check(order, :time)
    assert :ok = OrderLock.check(order, :items)
  end

  test "with the courier only the comment and cash or card swap" do
    order = @branch_id |> order_fixture() |> with_status(:delivering)
    assert {:error, :with_courier} = OrderLock.check(order, :items)
    assert {:error, :with_courier} = OrderLock.check(order, :address)
    assert :ok = OrderLock.check(order, :comment)
    assert :ok = OrderLock.check(order, {:payment_method, :card_offline})
  end

  test "channel orders change only the comment" do
    order =
      @branch_id
      |> order_fixture()
      |> Order.channel_changeset(%{provider: "yandex_eda", external_id: "y-1"})
      |> Repo.update!()

    assert OrderLock.allowed(order) == [:comment]
    assert :ok = OrderLock.editable(order)

    assert {:ok, %{comment: "без лука", total_amount: total}} =
             Orders.update_order(order, %{"comment" => "без лука", "cart_id" => order.cart_id})

    assert total == order.total_amount
  end

  test "crm orders follow the provider capabilities" do
    frontpad =
      @branch_id
      |> order_fixture()
      |> Order.crm_changeset(%{provider: "frontpad"})
      |> Repo.update!()

    assert {:error, :crm_order} = OrderLock.editable(frontpad)

    test_crm =
      @branch_id
      |> order_fixture()
      |> Order.crm_changeset(%{provider: "test_crm"})
      |> Repo.update!()

    assert OrderLock.allowed(test_crm) == [:address, :comment]
  end

  test "a paid order keeps its payment method" do
    order = order_fixture(@branch_id)
    [payment] = Payments.list(order.id)
    payment |> Payment.move_changeset(:paid) |> Repo.update!()

    assert {:error, :paid} = OrderLock.check(order, {:payment_method, :card_offline})
    assert :ok = OrderLock.check(order, :items)

    assert {:error, :paid} =
             Orders.update_payment_method(order, %{"payment_method" => "card_offline"})
  end

  test "reverting a completed order reopens its cash payment" do
    staff = admin()
    order = order_fixture(@branch_id)

    {:ok, order} =
      Enum.reduce([:accepted, :preparing, :ready, :completed], {:ok, order}, fn status,
                                                                                {:ok, o} ->
        Orders.advance_order(o, status, {:staff, staff})
      end)

    assert [%{status: :paid}] = Payments.list(order.id)
    assert :ok = OrderLock.revert(order)

    assert {:ok, %{status: :ready}} = Orders.revert_order_status(order, staff, "ошибка")
    assert [%{status: :pending, paid_at: nil}] = Payments.list(order.id)
  end

  test "a payment handed over by the courier blocks the revert" do
    order = order_fixture(@branch_id) |> with_status(:completed)
    [payment] = Payments.list(order.id)

    payment
    |> Ecto.Changeset.change(status: :paid, fiscalized_by: :us)
    |> Repo.update!()

    assert {:error, :paid} = OrderLock.revert(order)
  end
end
