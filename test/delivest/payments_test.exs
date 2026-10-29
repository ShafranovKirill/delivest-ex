defmodule Delivest.PaymentsTest do
  use Delivest.DataCase, async: true

  import Delivest.Factory
  import Delivest.OrderFixtures

  alias Delivest.Payments
  alias Delivest.Payments.Payment
  alias Delivest.Oms.Orders.StatusChange

  setup do
    %{branch: insert(:branch)}
  end

  defp operator(branch) do
    insert(:staff, role: build(:role, permissions: ["orders.update"]), branches: [branch])
    |> Repo.preload([:role, :branches])
  end

  test "a cash order expects the money and takes it on completion", %{branch: branch} do
    order =
      order_fixture(branch.id, price: 50_000, attrs: %{"cash_given" => "100000"})

    assert [%Payment{status: :pending, method: :cash, amount: 50_000, cash_given: 100_000}] =
             Payments.list(order.id)

    assert Payments.balance(order) == :unpaid

    staff = operator(branch)

    order =
      Enum.reduce([:accepted, :preparing, :ready, :completed], order, fn to, order ->
        {:ok, order} = StatusChange.run(order, to, {:staff, staff})
        order
      end)

    staff_id = staff.id

    assert [%Payment{status: :paid, paid_at: %DateTime{}, collected_by_id: ^staff_id}] =
             Payments.list(order.id)
    assert Payments.balance(order) == :paid
  end

  test "a cancelled order drops the expected payment", %{branch: branch} do
    order = order_fixture(branch.id, attrs: %{"payment_method" => "card_offline"})
    {:ok, order} = StatusChange.run(order, :cancelled, :system, attrs: %{cancel_reason: :other})

    assert [%Payment{status: :cancelled, method: :card}] = Payments.list(order.id)
    assert Payments.balance(order) == :unpaid
  end

  test "a refund is limited by what is left on the payment", %{branch: branch} do
    order = order_fixture(branch.id, price: 30_000)
    {:ok, order} = StatusChange.run(order, :completed, :system)
    [payment] = Payments.list(order.id)

    assert {:ok, _refund} = Payments.refund(payment, 10_000, %{reason: "cold"})
    assert {:error, :refund_too_large} = Payments.refund(payment, 25_000)
    assert Payments.balance(order) == :partially_paid

    assert {:ok, _refund} = Payments.refund(payment, 20_000)
    assert Payments.balance(order) == :refunded
  end

  test "the balance follows the paid sum" do
    paid = fn amount -> %Payment{status: :paid, amount: amount, refunds: []} end

    assert Payments.balance(1000, []) == :unpaid
    assert Payments.balance(1000, [paid.(400)]) == :partially_paid
    assert Payments.balance(1000, [paid.(400), paid.(600)]) == :paid
    assert Payments.balance(1000, [paid.(1500)]) == :overpaid
    assert Payments.balance(1000, [%Payment{status: :pending, amount: 1000}]) == :unpaid
  end
end
