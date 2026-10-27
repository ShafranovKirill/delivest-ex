defmodule Delivest.Integrations.YandexEda.OrderEventsTest do
  use Delivest.DataCase, async: true

  import Delivest.YandexEdaFixtures

  alias Delivest.Integrations.YandexEda
  alias Delivest.Oms.{Order, Orders}

  setup do
    branch = yandex_branch()
    product = menu_product(branch, menu_category(branch))
    {:ok, order} = YandexEda.create_order(order_params(branch, [product]))
    %{order: order}
  end

  defp reload(order), do: Repo.get!(Order, order.id)

  test "the status starts from the kitchen and only moves forward", %{order: order} do
    assert {:ok, %{status: "ACCEPTED_BY_RESTAURANT", updatedAt: updated_at}} =
             YandexEda.order_status(order.id)

    assert updated_at =~ ~r/\.\d{6}\+03:00$/

    {:ok, _} = Orders.update_order_details(reload(order), %{"status" => "ready"})
    assert {:ok, %{status: "READY"}} = YandexEda.order_status(order.id)

    {:ok, _} = Orders.update_order_details(reload(order), %{"status" => "preparing"})
    assert {:ok, %{status: "READY"}} = YandexEda.order_status(order.id)
  end

  test "yandex moves the courier statuses", %{order: order} do
    assert {:ok, _} =
             YandexEda.update_order_status(order.id, %{"status" => "TAKEN_BY_COURIER"})

    assert reload(order).channel.remote_status == "delivering"
    assert {:ok, %{status: "TAKEN_BY_COURIER"}} = YandexEda.order_status(order.id)

    assert {:ok, _} = YandexEda.update_order_status(order.id, %{"status" => "DELIVERED"})
    assert {:ok, _} = YandexEda.update_order_status(order.id, %{"status" => "TAKEN_BY_COURIER"})
    assert reload(order).channel.remote_status == "completed"

    assert {:error, :invalid_status} =
             YandexEda.update_order_status(order.id, %{"status" => "COOKING"})
  end

  test "a cancel from yandex cancels the order here", %{order: order} do
    assert {:ok, _} = YandexEda.cancel_order(order.id, "Клиент передумал")

    order = reload(order)
    assert order.status == :cancelled
    assert order.channel.remote_status == "cancelled"
    assert order.channel.details["cancel_comment"] == "Клиент передумал"
    assert order.cancel_note =~ "Клиент передумал"
    assert {:ok, %{status: "CANCELLED"}} = YandexEda.order_status(order.id)
  end

  test "the CANCELLED status is a cancel", %{order: order} do
    assert {:ok, _} =
             YandexEda.update_order_status(order.id, %{"status" => "CANCELLED", "comment" => "x"})

    assert reload(order).status == :cancelled
  end

  test "the courier is kept in the channel details", %{order: order} do
    courier = %{"name" => "Иван", "phone" => "+79990000000"}

    assert {:ok, _} =
             YandexEda.update_courier(order.id, %{
               "courier" => courier,
               "location" => %{"latitude" => 55.7, "longitude" => 37.6},
               "ignored" => true
             })

    details = reload(order).channel.details["courier"]
    assert details["courier"] == courier
    assert details["location"]
    refute details["ignored"]
  end

  test "orders from other sources and unknown ids are not found", %{order: order} do
    assert {:error, :order_not_found} = YandexEda.get_order("nope")
    assert {:error, :order_not_found} = YandexEda.get_order(Ecto.UUID.generate())
    assert {:ok, %Order{id: id}} = YandexEda.get_order(order.id)
    assert id == order.id
  end
end
