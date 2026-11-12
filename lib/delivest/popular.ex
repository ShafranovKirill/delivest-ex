defmodule Delivest.Popular do
  @moduledoc """
  Popular products of a branch, shown to customers in the app.

  Two modes: `:auto` computes the top products by sales for the current period,
  `:manual` uses the hand-picked list. The picked list stays in the database
  even while another mode is active, so switching back does not lose it.
  """

  import Ecto.Query

  alias Delivest.{Analytics, Audit, Identity, Repo}
  alias Delivest.Popular.{Entry, Settings}

  @auto_period_days 30

  def get_settings(branch_id),
    do: Repo.get_by(Settings, branch_id: branch_id) || %Settings{branch_id: branch_id}

  def change_settings(%Settings{} = settings, attrs \\ %{}),
    do: Settings.changeset(settings, attrs)

  def update_settings(staff, branch_id, attrs) do
    with :ok <- Identity.authorize(staff, "products.update", branch_id) do
      branch_id
      |> get_settings()
      |> Settings.changeset(attrs)
      |> Repo.insert_or_update()
    end
    |> Audit.track(staff, "popular.settings_updated")
  end

  def list_entries(branch_id) do
    from(e in Entry,
      where: e.branch_id == ^branch_id,
      order_by: [asc: e.position, asc: e.inserted_at, asc: e.id]
    )
    |> Repo.all()
  end

  def list_product_ids(branch_id), do: Enum.map(list_entries(branch_id), & &1.product_id)

  @doc "Products of the branch shown as popular, in display order."
  def list_products(branch_id) do
    case get_settings(branch_id).mode do
      :off -> []
      :auto -> auto_products(branch_id)
      :manual -> manual_products(branch_id)
    end
  end

  defp manual_products(branch_id) do
    ids = list_product_ids(branch_id)

    products =
      branch_id
      |> Delivest.Net.list_branch_products()
      |> Map.new(&{&1.id, &1})

    ids
    |> Enum.map(&Map.get(products, &1))
    |> Enum.reject(&is_nil/1)
  end

  defp auto_products(branch_id) do
    limit = get_settings(branch_id).auto_limit

    today = Delivest.LocalTime.today(Delivest.LocalTime.timezone(branch_id))
    from_date = Date.add(today, -(@auto_period_days - 1))

    by_id =
      branch_id
      |> Delivest.Net.list_branch_products()
      |> Map.new(&{&1.id, &1})

    branch_id
    |> Analytics.top_products({from_date, today}, limit: limit, sort_by: :quantity)
    |> Enum.map(&Map.get(by_id, &1.product_id))
    |> Enum.reject(&is_nil/1)
  end

  def add_product(staff, branch_id, product_id) do
    with :ok <- Identity.authorize(staff, "products.update", branch_id),
         {:ok, _product} <- fetch_branch_product(branch_id, product_id) do
      position = length(list_entries(branch_id))

      %Entry{}
      |> Entry.changeset(%{branch_id: branch_id, product_id: product_id, position: position})
      |> Repo.insert(on_conflict: :nothing, conflict_target: [:branch_id, :product_id])
    end
    |> Audit.track(staff, "popular.product_added")
  end

  def remove_product(staff, branch_id, product_id) do
    with :ok <- Identity.authorize(staff, "products.update", branch_id) do
      {_count, _} =
        from(e in Entry, where: e.branch_id == ^branch_id and e.product_id == ^product_id)
        |> Repo.delete_all()

      {:ok, :removed}
    end
    |> Audit.track(staff, "popular.product_removed")
  end

  def reorder(staff, branch_id, ids) do
    with :ok <- Identity.authorize(staff, "products.update", branch_id),
         true <- is_list(ids) and Enum.all?(ids, &is_binary/1) do
      Repo.transaction(fn ->
        Enum.each(Enum.with_index(ids), fn {id, position} ->
          from(e in Entry, where: e.branch_id == ^branch_id and e.product_id == ^id)
          |> Repo.update_all(set: [position: position])
        end)
      end)
      |> case do
        {:ok, _result} -> {:ok, list_entries(branch_id)}
        other -> other
      end
    else
      false -> {:error, :invalid_order}
      error -> error
    end
  end

  defp fetch_branch_product(branch_id, product_id) do
    branch_id
    |> Delivest.Net.list_branch_products()
    |> Enum.find(&(&1.id == product_id))
    |> case do
      nil -> {:error, :product_not_found}
      product -> {:ok, product}
    end
  end
end
