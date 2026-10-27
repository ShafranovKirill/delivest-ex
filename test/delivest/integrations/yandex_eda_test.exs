defmodule Delivest.Integrations.YandexEdaTest do
  use Delivest.DataCase, async: true

  import Delivest.Factory
  import Delivest.YandexEdaFixtures

  alias Delivest.Integrations.YandexEda

  describe "access" do
    test "a token is issued only for the right credentials" do
      settings = credentials()

      assert {:ok, token} = YandexEda.issue_token(settings.client_id, settings.client_secret)
      assert YandexEda.valid_token?(token)

      assert {:error, :invalid_client} = YandexEda.issue_token(settings.client_id, "wrong")
      refute YandexEda.valid_token?("garbage")
      refute YandexEda.valid_token?(nil)
    end

    test "without generated access no token is issued" do
      assert {:error, :invalid_client} = YandexEda.issue_token("", "")
    end

    test "a new secret revokes old tokens" do
      admin = insert(:staff, role: build(:role, permissions: ["admin"]))
      settings = credentials()
      {:ok, token} = YandexEda.issue_token(settings.client_id, settings.client_secret)

      assert {:ok, rotated} = YandexEda.rotate_credentials(admin)
      refute rotated.client_secret == settings.client_secret
      refute YandexEda.valid_token?(token)
    end

    test "only an admin changes the access" do
      staff = insert(:staff)
      assert {:error, :forbidden} = YandexEda.rotate_credentials(staff)
      assert {:error, :forbidden} = YandexEda.update_settings(staff, %{"partner_name" => "x"})
    end
  end

  describe "restaurants" do
    test "only branches with the channel are listed" do
      branch = yandex_branch([], city: "Москва", address: "Тверская, 1")
      off = yandex_branch(enabled: false)
      insert(:branch)

      ids = Enum.map(YandexEda.restaurants(), & &1.id)
      assert branch.id in ids
      assert off.id in ids
      assert length(ids) == 2

      assert %{title: _, address: "Москва, Тверская, 1"} =
               Enum.find(YandexEda.restaurants(), &(&1.id == branch.id))

      availability = Map.new(YandexEda.restaurants_availability(), &{&1.id, &1.enabled})
      assert availability == %{branch.id => true, off.id => false}
    end
  end

  describe "menu" do
    setup do
      branch = yandex_branch(markup_percent: 10, round_to: 10)
      category = menu_category(branch, name: "Супы")
      %{branch: branch, category: category}
    end

    test "the composition has the channel prices and skips switched off products", %{
      branch: branch,
      category: category
    } do
      soup = menu_product(branch, category, name: "Борщ", price: 300, weight: 350)
      tea = menu_product(branch, category, name: "Морс", price: 100, measure_unit: :ml)
      hidden = menu_product(branch, category, price: 100)
      staff = insert(:staff, role: build(:role, permissions: ["products.update"]))

      {:ok, _} = YandexEda.update_product(staff, tea.id, %{"price" => "150"})
      {:ok, _} = YandexEda.update_product(staff, hidden.id, %{"enabled" => "false"})

      assert {:ok, menu} = YandexEda.composition(branch.id)
      assert [%{id: category_id, name: "Супы", sortOrder: 0}] = menu.categories
      assert category_id == category.id
      assert menu.lastChange =~ ~r/\.\d{6}\+03:00$/

      items = Map.new(menu.items, &{&1.id, &1})
      refute Map.has_key?(items, hidden.id)
      assert %{price: 330, measure: 350, measureUnit: "г", name: "Борщ"} = items[soup.id]
      assert %{price: 150, measureUnit: "мл"} = items[tea.id]
    end

    test "only staff with product rights changes the channel menu", %{
      branch: branch,
      category: category
    } do
      soup = menu_product(branch, category)

      assert {:error, :forbidden} =
               YandexEda.update_product(insert(:staff), soup.id, %{"enabled" => "false"})
    end

    test "the stop list lists stopped products of the channel menu", %{
      branch: branch,
      category: category
    } do
      soup = menu_product(branch, category)
      hidden = menu_product(branch, category)
      staff = insert(:staff, role: build(:role, permissions: ["products.update"]))
      {:ok, _} = YandexEda.update_product(staff, hidden.id, %{"enabled" => "false"})

      for product <- [soup, hidden] do
        Repo.insert!(%Delivest.Net.ProductStop{
          branch_id: branch.id,
          product_id: product.id,
          source: Delivest.Net.ProductStop.manual()
        })
      end

      Cachex.del(:stop_cache, branch.id)

      assert {:ok, %{items: [%{itemId: id, stock: 0}], modifiers: []}} =
               YandexEda.availability(branch.id)

      assert id == soup.id
    end

    test "the schedule comes from the working hours" do
      branch =
        yandex_branch([],
          working_hours: %{
            "monday" => %{"enabled" => true, "open" => "10:00", "close" => "23:00"}
          }
        )

      assert {:ok, %{"mon" => [%{start: "10:00", end: "23:00"}]}} =
               YandexEda.schedule(branch.id)
    end

    test "a disabled restaurant has no menu" do
      branch = yandex_branch(enabled: false)
      assert {:error, :restaurant_not_found} = YandexEda.composition(branch.id)
      assert {:error, :restaurant_not_found} = YandexEda.availability("nope")
    end
  end
end
