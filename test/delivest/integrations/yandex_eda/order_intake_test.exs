defmodule Delivest.Integrations.YandexEda.OrderIntakeTest do
  use Delivest.DataCase, async: true

  import Delivest.YandexEdaFixtures

  alias Delivest.Integrations.Channels.ChannelProduct
  alias Delivest.Integrations.Crm.BranchSettings, as: CrmSettings
  alias Delivest.Integrations.Frontpad
  alias Delivest.Integrations.YandexEda
  alias Delivest.Net.ProductStop
  alias Delivest.Oms.Order

  setup do
    branch = yandex_branch()
    category = menu_category(branch)
    soup = menu_product(branch, category, name: "Суп", price: 30_000)
    tea = menu_product(branch, category, name: "Чай", price: 10_000)
    %{branch: branch, soup: soup, tea: tea}
  end

  test "an order is accepted with the prices of yandex", %{branch: branch, soup: soup, tea: tea} do
    params = order_params(branch, [{soup, 2}, tea], %{"paymentInfo" => pay(650)})

    assert {:ok, %Order{} = order} = YandexEda.create_order(params)
    order = Repo.preload(order, :items)

    assert order.source == "yandex_eda"
    assert order.status == :accepted
    assert order.fulfillment_type == :pickup
    assert order.payment_method == :online
    assert order.total_amount == 65_000
    assert order.channel.external_id == params["eatsId"]
    assert order.channel.platform == "YE"
    assert order.channel.details["phone"] == "+79990001122"
    assert order.comment =~ "Без лука"
    assert order.comment =~ "2"
    assert Enum.sort(Enum.map(order.items, & &1.quantity)) == [1, 2]
  end

  test "the same eatsId returns the same order", %{branch: branch, soup: soup} do
    params = order_params(branch, [soup])

    assert {:ok, first} = YandexEda.create_order(params)
    assert {:ok, second} = YandexEda.create_order(params)
    assert first.id == second.id
  end

  test "manual confirmation leaves the order new with a deadline" do
    branch = yandex_branch(accept_mode: :manual, accept_minutes: 7)
    product = menu_product(branch, menu_category(branch))

    assert {:ok, %Order{status: :created} = order} =
             YandexEda.create_order(order_params(branch, [product]))

    assert {:ok, deadline, _} = DateTime.from_iso8601(order.channel.details["accept_by"])
    assert DateTime.diff(deadline, DateTime.utc_now(), :minute) in 6..7
  end

  test "stopped and switched off products are unavailable", %{
    branch: branch,
    soup: soup,
    tea: tea
  } do
    Repo.insert!(%ProductStop{
      branch_id: branch.id,
      product_id: soup.id,
      source: ProductStop.manual()
    })

    Cachex.del(:stop_cache, branch.id)
    Repo.insert!(%ChannelProduct{channel: "yandex_eda", product_id: tea.id, enabled: false})

    assert {:error, {:unavailable, items}} =
             YandexEda.create_order(order_params(branch, [soup, tea]))

    assert items |> Enum.map(& &1.product_id) |> Enum.sort() == Enum.sort([soup.id, tea.id])
  end

  test "an unknown or disabled restaurant is not found", %{soup: soup} do
    branch = yandex_branch(enabled: false)

    assert {:error, :restaurant_not_found} =
             YandexEda.create_order(order_params(branch, [soup]))

    assert {:error, :restaurant_not_found} =
             YandexEda.create_order(order_params(%{id: Ecto.UUID.generate()}, [soup]))
  end

  test "a cash marketplace order goes to delivery with the change in the comment", %{
    branch: branch,
    soup: soup
  } do
    params =
      branch
      |> order_params([soup])
      |> marketplace()
      |> Map.put("paymentInfo", %{
        "paymentType" => "CASH",
        "itemsCost" => 300,
        "deliveryFee" => 99,
        "change" => 500
      })

    assert {:ok, %Order{} = order} = YandexEda.create_order(params)
    assert order.fulfillment_type == :delivery
    assert order.delivery_amount == 9900
    assert order.total_amount == 39_900
    assert order.payment_method == :cash
    assert order.address.formatted == "Москва, Тверская улица, 1"
    assert order.address.latitude == 55.757
    assert order.comment =~ "500"
  end

  test "the order goes to the crm when yandex is one of its sources", %{soup: soup} do
    branch =
      yandex_branch([],
        crm: %CrmSettings{
          enabled: true,
          provider: :frontpad,
          sources: ["yandex_eda"],
          frontpad: %Frontpad.Settings{api_key: "key", webhook_token: "t"}
        }
      )

    product = menu_product(branch, menu_category(branch), price: soup.price)

    assert {:ok, %Order{status: :accepted, crm: %{provider: "frontpad"}}} =
             YandexEda.create_order(order_params(branch, [product]))
  end

  defp pay(cost), do: %{"paymentType" => "CARD", "itemsCost" => cost}
end
