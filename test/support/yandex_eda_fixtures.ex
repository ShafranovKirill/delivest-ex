defmodule Delivest.YandexEdaFixtures do
  import Delivest.Factory

  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Integrations.Channels
  alias Delivest.Integrations.YandexEda.{BranchSettings, Settings}
  alias Delivest.Repo

  def yandex_branch(settings \\ [], info \\ []) do
    branch = insert(:branch, is_active: true)

    Repo.insert!(
      struct!(
        %BranchInfo{
          branch_id: branch.id,
          channels: %Channels.BranchSettings{
            yandex_eda: struct!(%BranchSettings{enabled: true}, settings)
          }
        },
        info
      )
    )

    branch
  end

  def menu_category(branch, attrs \\ []) do
    category = insert(:category, attrs)

    {:ok, _relation} =
      Delivest.Relations.create_relation(Repo, "Branch", branch.id, "Category", category.id)

    category
  end

  def menu_product(branch, category, attrs \\ []),
    do: insert_branch_product(branch.id, Keyword.put(attrs, :category_id, category.id))

  def credentials do
    {:ok, settings} = %Settings{} |> Settings.changeset(%{}) |> Repo.insert()
    settings
  end

  def order_params(branch, items, overrides \\ %{}) do
    %{
      "discriminator" => "pickup",
      "eatsId" => "260427-#{System.unique_integer([:positive])}",
      "restaurantId" => branch.id,
      "platform" => "YE",
      "comment" => "Без лука",
      "persons" => 2,
      "items" => Enum.map(items, &item/1),
      "paymentInfo" => %{"paymentType" => "CARD", "itemsCost" => items_cost(items)},
      "deliveryInfo" => %{
        "clientName" => "Анна",
        "phoneNumber" => "+79990001122",
        "clientArrivementDate" => "2026-10-27T12:30:00.000000+03:00"
      }
    }
    |> Map.merge(overrides)
  end

  def marketplace(params) do
    Map.merge(params, %{
      "discriminator" => "marketplace",
      "deliveryInfo" => %{
        "clientName" => "Анна",
        "phoneNumber" => "+79990001122",
        "deliveryDate" => "2026-10-27T13:00:00.000000+03:00",
        "deliveryAddress" => %{
          "full" => "Москва, Тверская улица, 1",
          "latitude" => "55.757",
          "longitude" => "37.613"
        }
      }
    })
  end

  defp item({product, quantity}),
    do: %{
      "id" => product.id,
      "name" => product.name,
      "quantity" => quantity,
      "price" => product.price
    }

  defp item(product), do: item({product, 1})

  defp items_cost(items) do
    items
    |> Enum.map(fn
      {product, quantity} -> product.price * quantity
      product -> product.price
    end)
    |> Enum.sum()
  end
end
