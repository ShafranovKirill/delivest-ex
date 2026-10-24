defmodule Delivest.Net.BranchScope do
  alias Delivest.Net.{Category, Product, Stock}
  alias Delivest.{Relations, Repo}

  @types %{Product => "Product", Category => "Category", Stock => "Stock"}

  def fetch(schema, branch_id, id, opts \\ []) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         true <- belongs?(schema, branch_id, uuid),
         record when not is_nil(record) <- Repo.get(schema, uuid),
         false <- deleted?(record) do
      {:ok, Repo.preload(record, Keyword.get(opts, :preload, []))}
    else
      _ -> {:error, :not_found}
    end
  end

  def belongs?(_schema, nil, _id), do: false

  def belongs?(schema, branch_id, id),
    do: Relations.related?("Branch", branch_id, Map.fetch!(@types, schema), id)

  defp deleted?(%{deleted_at: %DateTime{}}), do: true
  defp deleted?(_record), do: false
end
