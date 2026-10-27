defmodule Delivest.Integrations.YandexEda.Menu do
  alias Delivest.Integrations.Channels.Products
  alias Delivest.Integrations.YandexEda.{Clock, MenuItem, Price}
  alias Delivest.Net

  @channel :yandex_eda

  def catalog(branch, settings) do
    channel_products = Products.by_product(@channel)

    for category <- Net.list_category_for_branch(branch.id),
        {product, index} <- Enum.with_index(category.products) do
      channel_product = channel_products[product.id]

      %{
        category: category,
        product: product,
        index: index,
        channel_product: channel_product,
        enabled: Products.enabled?(channel_product),
        price: Price.of(product, channel_product, settings)
      }
    end
  end

  def offer(branch, settings) do
    for entry <- catalog(branch, settings),
        entry.enabled and entry.price > 0,
        do: {entry.category, entry.product, entry.index, entry.price}
  end

  def product_ids(branch, settings),
    do: for({_category, product, _index, _price} <- offer(branch, settings), do: product.id)

  def composition(branch, settings) do
    offer = offer(branch, settings)
    categories = offer |> Enum.map(&elem(&1, 0)) |> Enum.uniq_by(& &1.id)

    %{
      categories: categories |> Enum.with_index() |> Enum.map(&category/1),
      items: Enum.map(offer, &MenuItem.build(&1, settings)),
      lastChange: offer |> last_change(categories, branch) |> Clock.format()
    }
  end

  defp category({category, index}),
    do: %{id: category.id, name: category.name, sortOrder: index}

  defp last_change(offer, categories, branch) do
    products = Enum.map(offer, &elem(&1, 1))

    [
      Products.last_change(@channel, Enum.map(products, & &1.id)),
      branch.info && branch.info.updated_at
      | Enum.map(products ++ categories, & &1.updated_at)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&to_datetime/1)
    |> Enum.max(DateTime, fn -> DateTime.from_unix!(0) end)
  end

  defp to_datetime(%NaiveDateTime{} = naive), do: DateTime.from_naive!(naive, "Etc/UTC")
  defp to_datetime(%DateTime{} = datetime), do: datetime
end
