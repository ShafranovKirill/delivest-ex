defmodule Delivest.AnalyticsTest do
  use Delivest.DataCase, async: true

  import Delivest.Factory

  alias Delivest.Analytics
  alias Delivest.Oms.{Carts, Order, Orders}

  @branch_id "00000000-0000-4000-8000-0000000000a1"
  @other_branch_id "00000000-0000-4000-8000-0000000000b2"

  setup do
    drinks = insert(:category, name: "Напитки")
    food = insert(:category, name: "Горячее")

    %{
      tea: insert_branch_product(@branch_id, name: "Чай", price: 100, category_id: drinks.id),
      khinkali:
        insert_branch_product(@branch_id, name: "Хинкали", price: 300, category_id: food.id),
      foreign: insert_branch_product(@other_branch_id, name: "Чужое", price: 999)
    }
  end

  defp order!(branch_id, lines, at, attrs \\ %{}) do
    {:ok, cart} =
      Carts.create_cart(%{session_id: "s-#{System.unique_integer()}", branch_id: branch_id})

    for {product, qty} <- lines, do: {:ok, _, _} = Carts.add_item(cart.id, product.id, qty)

    {:ok, order} =
      Orders.create_order(
        Map.merge(
          %{"cart_id" => cart.id, "fulfillment_type" => "pickup", "payment_method" => "cash"},
          attrs
        )
      )

    order |> Ecto.Changeset.change(inserted_at: at) |> Repo.update!()
  end

  test "summary counts only sold orders of the branch within the period", ctx do
    order!(@branch_id, [{ctx.tea, 2}, {ctx.khinkali, 1}], ~U[2026-10-18 22:30:00Z])
    order!(@branch_id, [{ctx.khinkali, 2}], ~U[2026-10-19 12:00:00Z])

    cancelled = order!(@branch_id, [{ctx.tea, 5}], ~U[2026-10-19 13:00:00Z])

    {:ok, _} = Orders.cancel_order(cancelled, :system, %{"cancel_reason" => "other"})

    deleted = order!(@branch_id, [{ctx.tea, 7}], ~U[2026-10-19 14:00:00Z])
    {:ok, _} = Orders.soft_delete_order(deleted)

    order!(@other_branch_id, [{ctx.foreign, 1}], ~U[2026-10-19 12:00:00Z])
    order!(@branch_id, [{ctx.tea, 1}], ~U[2026-10-20 12:00:00Z])

    summary = Analytics.summary(@branch_id, {~D[2026-10-19], ~D[2026-10-19]})

    assert summary.orders_count == 2
    assert summary.revenue == 2 * 100 + 300 + 2 * 300
    assert summary.avg_check == 550
    assert summary.items_sold == 5
    assert summary.cancelled_count == 1
  end

  test "daily fills empty days and buckets by local date", ctx do
    order!(@branch_id, [{ctx.tea, 1}], ~U[2026-10-18 22:30:00Z])

    assert [
             %{date: ~D[2026-10-18], orders: 0, revenue: 0},
             %{date: ~D[2026-10-19], orders: 1, revenue: 100},
             %{date: ~D[2026-10-20], orders: 0, revenue: 0}
           ] = Analytics.daily(@branch_id, {~D[2026-10-18], ~D[2026-10-20]})
  end

  test "hourly uses local hours", ctx do
    order!(@branch_id, [{ctx.tea, 1}], ~U[2026-10-19 09:15:00Z])

    hours = Analytics.hourly(@branch_id, {~D[2026-10-19], ~D[2026-10-19]})
    assert length(hours) == 24
    assert Enum.at(hours, 12) == %{hour: 12, orders: 1, revenue: 100}
  end

  test "top products and categories with shares", ctx do
    order!(@branch_id, [{ctx.tea, 3}, {ctx.khinkali, 1}], ~U[2026-10-19 12:00:00Z])
    order!(@branch_id, [{ctx.khinkali, 1}], ~U[2026-10-19 13:00:00Z])

    period = {~D[2026-10-19], ~D[2026-10-19]}

    assert [
             %{title: "Хинкали", quantity: 2, revenue: 600, orders: 2, share: 66.7},
             %{title: "Чай", quantity: 3, revenue: 300, orders: 1, share: 33.3}
           ] = Analytics.top_products(@branch_id, period)

    assert [%{title: "Чай"}, %{title: "Хинкали"}] =
             Analytics.top_products(@branch_id, period, sort_by: :quantity)

    assert [
             %{category_name: "Горячее", revenue: 600, quantity: 2},
             %{category_name: "Напитки", revenue: 300, quantity: 3}
           ] = Analytics.categories(@branch_id, period)
  end

  test "category snapshot survives catalog changes", ctx do
    order!(@branch_id, [{ctx.tea, 1}], ~U[2026-10-19 12:00:00Z])

    Repo.update_all(Delivest.Net.Category, set: [name: "Переименовано"])

    assert [%{category_name: "Напитки"}] =
             Analytics.categories(@branch_id, {~D[2026-10-19], ~D[2026-10-19]})
  end

  test "breakdown by fulfillment type", ctx do
    order!(@branch_id, [{ctx.tea, 1}], ~U[2026-10-19 12:00:00Z])

    order!(@branch_id, [{ctx.tea, 1}], ~U[2026-10-19 12:00:00Z], %{
      "fulfillment_type" => "dine_in"
    })

    order!(@branch_id, [{ctx.tea, 1}], ~U[2026-10-19 12:00:00Z], %{
      "fulfillment_type" => "dine_in"
    })

    assert [%{key: :dine_in, orders: 2, share: 66.7}, %{key: :pickup, orders: 1}] =
             Analytics.breakdown(@branch_id, {~D[2026-10-19], ~D[2026-10-19]}, :fulfillment_type)
  end

  test "client summary is limited to the given branches", ctx do
    client = insert(:client)
    first = order!(@branch_id, [{ctx.tea, 2}], ~U[2026-10-18 12:00:00Z])
    second = order!(@branch_id, [{ctx.khinkali, 1}], ~U[2026-10-19 12:00:00Z])
    other = order!(@other_branch_id, [{ctx.foreign, 1}], ~U[2026-10-19 12:00:00Z])

    for order <- [first, second, other] do
      Repo.update!(Ecto.Changeset.change(order, client_id: client.id))
    end

    all = Analytics.client_summary(client.id, :all)
    assert all.orders_count == 3
    assert all.spent == 200 + 300 + 999

    scoped = Analytics.client_summary(client.id, [@branch_id])
    assert scoped.orders_count == 2
    assert scoped.spent == 500
    assert scoped.avg_check == 250
    assert [%{title: "Чай", quantity: 2}, %{title: "Хинкали", quantity: 1}] = scoped.favourites
  end

  test "resolve_period presets" do
    today = Delivest.LocalTime.today()

    assert Analytics.resolve_period("today") == {today, today}
    assert Analytics.resolve_period("week") == {Date.add(today, -6), today}

    assert Analytics.resolve_period("custom", "2026-10-10", "2026-10-01") ==
             {~D[2026-10-01], ~D[2026-10-10]}

    assert Analytics.previous_period({~D[2026-10-08], ~D[2026-10-14]}) ==
             {~D[2026-10-01], ~D[2026-10-07]}
  end

  test "order items keep their category", ctx do
    order = order!(@branch_id, [{ctx.khinkali, 1}], ~U[2026-10-19 12:00:00Z])
    [item] = Repo.preload(order, :items).items

    assert item.category_name == "Горячее"
    assert %Order{} = order
  end

  defp crm!(order, crm) do
    order
    |> Ecto.Changeset.change(status: crm_status(crm))
    |> Order.crm_changeset(Map.put(crm, :provider, "frontpad"))
    |> Repo.update!()
  end

  defp crm_status(%{remote_status: status}), do: String.to_existing_atom(status)
  defp crm_status(%{status: "sent"}), do: :accepted
  defp crm_status(_crm), do: :created

  test "crm orders cancelled remotely or never delivered are not sales", ctx do
    period = {~D[2026-10-19], ~D[2026-10-19]}

    order!(@branch_id, [{ctx.tea, 1}], ~U[2026-10-19 10:00:00Z])
    |> crm!(%{status: "sent", remote_status: "completed"})

    order!(@branch_id, [{ctx.tea, 2}], ~U[2026-10-19 11:00:00Z])
    |> crm!(%{status: "sent", remote_status: "cancelled"})

    order!(@branch_id, [{ctx.tea, 3}], ~U[2026-10-19 12:00:00Z])
    |> crm!(%{status: "failed"})

    order!(@branch_id, [{ctx.tea, 4}], ~U[2026-10-19 13:00:00Z])
    |> crm!(%{status: "sent"})

    assert %{revenue: 500, orders_count: 2, cancelled_count: 1, lost_count: 1} =
             Analytics.summary(@branch_id, period)

    assert %{completed: 1, cancelled: 1, created: 1, accepted: 1} =
             Analytics.status_counts(@branch_id, period)
  end
end
