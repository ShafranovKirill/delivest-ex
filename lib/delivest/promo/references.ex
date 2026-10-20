defmodule Delivest.Promo.References do
  import Ecto.Changeset

  use Gettext, backend: DelivestWeb.Gettext

  alias Delivest.Net
  alias Delivest.Promo.{Dsl, Strategy}

  def validate(%Ecto.Changeset{} = changeset, branch_id) do
    with true <- changeset.valid?,
         {:ok, strategy} <- Dsl.parse(get_field(changeset, :rules)) do
      changeset |> add_missing(missing(strategy, branch_id))
    else
      _ -> changeset
    end
  end

  def missing(%Strategy{} = strategy, branch_id) do
    slugs = Strategy.slugs(strategy)
    found = Net.list_branch_products_by_slugs(branch_id, slugs)
    Enum.reject(slugs, &Map.has_key?(found, &1))
  end

  defp add_missing(changeset, slugs) do
    Enum.reduce(slugs, changeset, fn slug, acc ->
      add_error(acc, :rules, gettext("Product «%{slug}» is not found in the branch", slug: slug))
    end)
  end
end
