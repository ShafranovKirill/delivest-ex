defmodule Delivest.Oms.OnlineHandoverGateTest do
  use Delivest.DataCase, async: true

  import Delivest.Factory
  import Delivest.OrderFixtures

  alias Delivest.Oms.{Order, Orders, OrderTransition}
  alias Delivest.Payments.{Payment, Refund}
  alias DelivestWeb.Staff.OrderLive.StatusErrors

  defp online_order(changes \\ []) do
    branch = insert(:branch)

    order =
      branch.id
      |> order_fixture()
      |> Ecto.Changeset.change(
        Keyword.merge(
          [payment_method: :online, fulfillment_type: :delivery, status: :ready],
          changes
        )
      )
      |> Repo.update!()

    payment =
      Payment
      |> where([p], p.order_id == ^order.id)
      |> Repo.one!()
      |> Ecto.Changeset.change(method: :online, provider: "yookassa")
      |> Repo.update!()

    {order, payment, branch}
  end

  defp staff(branch) do
    insert(:staff, role: build(:role, permissions: ["orders.update"]), branches: [branch])
    |> Repo.preload([:role, :branches])
  end

  defp paid(payment, attrs \\ []) do
    payment
    |> Ecto.Changeset.change(
      Keyword.merge([status: :paid, paid_at: DateTime.utc_now(:second)], attrs)
    )
    |> Repo.update!()
  end

  defp refund(payment, amount, status) do
    %Refund{}
    |> Refund.changeset(%{
      payment_id: payment.id,
      order_id: payment.order_id,
      amount: amount,
      status: status
    })
    |> Repo.insert!()
  end

  test "staff may accept and prepare an authorized order, but cannot hand it over" do
    {order, payment, branch} = online_order(status: :created)
    payment |> Ecto.Changeset.change(status: :authorized) |> Repo.update!()
    actor = {:staff, staff(branch)}

    {:ok, accepted} = Orders.advance_order(order, :accepted, actor)
    {:ok, preparing} = Orders.advance_order(accepted, :preparing, actor)
    {:ok, ready} = Orders.advance_order(preparing, :ready, actor)

    assert {:error, :online_payment_not_captured} =
             Orders.advance_order(ready, :delivering, actor)

    assert Repo.reload!(order).status == :ready

    refute Repo.exists?(
             where(OrderTransition, [t], t.order_id == ^order.id and t.to == :delivering)
           )
  end

  test "staff completion requires a confirmed exact net payment" do
    {order, payment, branch} = online_order(fulfillment_type: :pickup)
    actor = {:staff, staff(branch)}

    assert {:error, :online_payment_not_captured} =
             Orders.advance_order(order, :completed, actor)

    payment |> paid(paid_at: nil)

    assert {:error, :online_payment_not_captured} =
             Orders.advance_order(order, :completed, actor)

    paid(payment)
    assert {:ok, %Order{status: :completed}} = Orders.advance_order(order, :completed, actor)
  end

  test "courier pickup and external leaps cannot advance before capture or persist extra changes" do
    {order, payment, branch} = online_order()
    courier = staff(branch)

    assert {:error, :online_payment_not_captured} =
             Orders.advance_order(order, :delivering, {:courier, courier})

    assert {:error, :online_payment_not_captured} =
             Orders.advance_order(order, :completed, :delivery,
               with: &Ecto.Changeset.put_change(&1, :comment, "remote applied")
             )

    assert Repo.reload!(order).status == :ready
    assert Repo.reload!(order).comment != "remote applied"

    paid(payment)

    assert {:ok, %Order{status: :delivering}} =
             Orders.advance_order(order, :delivering, {:courier, courier})
  end

  test "pending refunds do not reduce captured net, succeeded refunds do" do
    {order, payment, _branch} = online_order()
    paid(payment)
    pending = refund(payment, 100, :pending)

    assert {:ok, %Order{status: :delivering}} =
             Orders.advance_order(order, :delivering, :delivery)

    pending |> Ecto.Changeset.change(status: :succeeded) |> Repo.update!()

    assert {:error, :online_payment_amount_mismatch} =
             Orders.advance_order(Repo.reload!(order), :completed, :delivery)
  end

  test "a different provider does not satisfy the online payment gate" do
    {order, payment, _branch} = online_order()
    paid(payment, provider: "other")

    assert {:error, :online_payment_not_captured} =
             Orders.advance_order(order, :delivering, :delivery)
  end

  test "only an exact captured net amount permits handover" do
    {order, payment, _branch} = online_order()
    payment |> paid(amount: order.total_amount - 100)

    assert {:error, :online_payment_amount_mismatch} =
             Orders.advance_order(order, :delivering, :delivery)

    payment
    |> Ecto.Changeset.change(amount: order.total_amount + 100)
    |> Repo.update!()

    assert {:error, :online_payment_amount_mismatch} =
             Orders.advance_order(order, :delivering, :delivery)

    refund(payment, 100, :succeeded)

    assert {:ok, %Order{status: :delivering}} =
             Orders.advance_order(order, :delivering, :delivery)
  end

  test "cash and externally paid channel orders do not use the YooKassa gate" do
    {order, _payment, _branch} = online_order(payment_method: :cash)

    assert {:ok, %Order{status: :delivering}} =
             Orders.advance_order(order, :delivering, :delivery)

    {external, _payment, _branch} = online_order()

    external =
      external
      |> Order.channel_changeset(%{provider: "yandex_eda", external_id: "external-1"})
      |> Repo.update!()

    assert {:ok, %Order{status: :delivering}} =
             Orders.advance_order(external, :delivering, :channel)
  end

  test "operator and courier share an actionable Russian error" do
    Gettext.with_locale(DelivestWeb.Gettext, "ru", fn ->
      assert StatusErrors.message({:error, :online_payment_not_captured}) ==
               "Дождитесь подтверждения оплаты от ЮKassa и повторите действие."

      assert StatusErrors.message({:error, :online_payment_amount_mismatch}) ==
               "Сумма оплаты ЮKassa не совпадает с итогом заказа. Проверьте оплату и возвраты в заказе."
    end)
  end
end
