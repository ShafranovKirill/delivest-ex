defmodule Delivest.Net.ProductCrmIds do
  import Ecto.Changeset
  import Ecto.Query, only: [from: 2]

  alias Delivest.Net.{Product, ProductExternalId}
  alias Delivest.Repo

  def by_product(product_ids, provider) do
    from(e in ProductExternalId,
      where: e.product_id in ^product_ids and e.provider == ^to_string(provider),
      select: {e.product_id, e.external_id}
    )
    |> Repo.all()
    |> Map.new()
  end

  def by_external_id(branch_id, provider) do
    from(e in ProductExternalId,
      where: e.branch_id == ^branch_id and e.provider == ^to_string(provider),
      select: {e.external_id, e.product_id}
    )
    |> Repo.all()
    |> Map.new()
  end

  def get(%Product{external_ids: ids}, provider) when is_list(ids),
    do: Enum.find_value(ids, &(&1.provider == to_string(provider) && &1.external_id))

  def get(_product, _provider), do: nil

  def load(%Product{external_ids: ids} = product) when is_list(ids),
    do: %{product | crm_ids: Map.new(ids, &{&1.provider, &1.external_id})}

  def load(product), do: product

  def put(%Ecto.Changeset{} = changeset, branch_id) do
    case fetch_change(changeset, :crm_ids) do
      {:ok, crm_ids} ->
        put_assoc(changeset, :external_ids, changes(changeset.data, crm_ids, branch_id))

      :error ->
        changeset
    end
  end

  def lift_errors(%Ecto.Changeset{changes: %{external_ids: children}} = changeset) do
    children
    |> Enum.flat_map(& &1.errors)
    |> Enum.reduce(changeset, fn {_field, {message, opts}}, acc ->
      add_error(acc, :crm_ids, message, opts)
    end)
  end

  def lift_errors(changeset), do: changeset

  defp changes(product, crm_ids, branch_id) do
    existing = existing(product)

    existing
    |> Map.keys()
    |> Enum.concat(Map.keys(crm_ids))
    |> Enum.uniq()
    |> Enum.flat_map(fn provider ->
      current = Map.get(existing, provider)
      value = crm_ids |> Map.get(provider, current && current.external_id) |> present()
      change_for(current, provider, value, branch_id)
    end)
  end

  defp existing(%Product{external_ids: ids}) when is_list(ids),
    do: Map.new(ids, &{&1.provider, &1})

  defp existing(_product), do: %{}

  defp change_for(_current, _provider, nil, _branch_id), do: []

  defp change_for(nil, provider, value, branch_id) do
    attrs = %{branch_id: branch_id, provider: provider, external_id: value}
    [ProductExternalId.changeset(%ProductExternalId{}, attrs)]
  end

  defp change_for(current, _provider, value, _branch_id),
    do: [ProductExternalId.changeset(current, %{external_id: value})]

  defp present(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp present(_value), do: nil
end
