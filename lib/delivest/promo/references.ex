defmodule Delivest.Promo.References do
  import Ecto.Changeset

  use Gettext, backend: DelivestWeb.Gettext

  alias Delivest.Net
  alias Delivest.Promo.{Dsl, Strategy}

  def validate(%Ecto.Changeset{} = changeset, branch_id) do
    with true <- changeset.valid?,
         {:ok, strategy} <- Dsl.parse(get_field(changeset, :rules)) do
      changeset
      |> add_missing(missing(strategy, branch_id))
      |> validate_choices(strategy, branch_id)
    else
      _ -> changeset
    end
  end

  def missing(%Strategy{} = strategy, branch_id) do
    slugs = Strategy.slugs(strategy)
    found = Net.list_branch_products_by_slugs(branch_id, slugs)
    Enum.reject(slugs, &Map.has_key?(found, &1))
  end

  defp validate_choices(changeset, strategy, branch_id) do
    products = Net.list_branch_products_by_slugs(branch_id, Strategy.slugs(strategy))
    stopped = Net.Stops.stopped_ids(branch_id)

    Enum.reduce(strategy.effects, changeset, fn
      {:gift_any, slugs, count}, acc ->
        available =
          Enum.count(slugs, fn slug ->
            case products[slug] do
              nil -> false
              product -> not MapSet.member?(stopped, product.id)
            end
          end)

        if available < count,
          do: add_error(acc, :rules, gettext("Not enough available gifts")),
          else: acc

      _, acc ->
        acc
    end)
  end

  defp add_missing(changeset, slugs) do
    Enum.reduce(slugs, changeset, fn slug, acc ->
      add_error(acc, :rules, gettext("Product «%{slug}» is not found in the branch", slug: slug))
    end)
  end
end
