defmodule Delivest.Popular do
  @moduledoc """
  Popular products of a branch, shown to customers in the app.

  Two modes: `:auto` computes the top products by sales for the current period,
  `:manual` uses the hand-picked list. The picked list stays in the database
  even while another mode is active, so switching back does not lose it.
  """

  import Ecto.Query

  alias Delivest.{Analytics, Audit, Identity, Repo}
  alias Delivest.Net.Catalogs
  alias Delivest.Popular.{Entry, Settings}

  @auto_period_days 30

  def get_settings(branch_id),
    do: Repo.get_by(Settings, branch_id: branch_id) || %Settings{branch_id: branch_id}

  def change_settings(%Settings{} = settings, attrs \\ %{}),
    do: Settings.changeset(settings, attrs)

  def update_settings(staff, branch_id, attrs) do
    with :ok <- Identity.authorize(staff, "products.update", branch_id) do
      result =
        Repo.transaction(fn ->
          lock_branch(branch_id)
          old = get_settings(branch_id)

          case old |> Settings.changeset(attrs) |> Repo.insert_or_update() do
            {:ok, settings} ->
              if refresh_on_update?(old, settings),
                do: refresh_snapshot!(settings),
                else: settings

            {:error, changeset} ->
              Repo.rollback(changeset)
          end
        end)

      if match?({:ok, _}, result), do: Catalogs.clear_menu_cache(branch_id)
      result
    end
    |> Audit.track(staff, "popular.settings_updated")
  end

  def recalculate(staff, branch_id) do
    with :ok <- Identity.authorize(staff, "products.update", branch_id) do
      recalculate_branch(branch_id)
    end
    |> Audit.track(staff, "popular.recalculated")
  end

  def recalculate_branch(branch_id, force? \\ true) do
    result =
      Repo.transaction(fn ->
        lock_branch(branch_id)
        settings = get_settings(branch_id)

        if settings.mode == :auto and
             (force? or Delivest.Popular.RefreshWorker.due?(settings, DateTime.utc_now())) do
          refresh_snapshot!(settings)
        else
          settings
        end
      end)

    if match?({:ok, _}, result), do: Catalogs.clear_menu_cache(branch_id)
    result
  end

  defp lock_branch(branch_id) do
    Repo.query!("SELECT pg_advisory_xact_lock(hashtext($1))", [branch_id])
  end

  defp refresh_on_update?(old, settings) do
    settings.mode == :auto and (settings.show_in_menu or settings.show_in_cart) and
      (old.mode != :auto or old.auto_limit != settings.auto_limit or
         (not old.show_in_menu and settings.show_in_menu) or
         (not old.show_in_cart and settings.show_in_cart))
  end

  defp refresh_snapshot!(settings) do
    today = Delivest.LocalTime.today(Delivest.LocalTime.timezone(settings.branch_id))
    from_date = Date.add(today, -(@auto_period_days - 1))

    ids =
      settings.branch_id
      |> Analytics.top_products({from_date, today},
        limit: settings.auto_limit,
        sort_by: :quantity
      )
      |> Enum.map(& &1.product_id)

    settings
    |> Ecto.Changeset.change(auto_product_ids: ids, calculated_at: DateTime.utc_now(:second))
    |> Repo.update!()
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
      :auto -> products_by_ids(branch_id, get_settings(branch_id).auto_product_ids)
      :manual -> manual_products(branch_id)
    end
  end

  defp manual_products(branch_id) do
    products_by_ids(branch_id, list_product_ids(branch_id))
  end

  defp products_by_ids(branch_id, ids) do
    products =
      branch_id
      |> Delivest.Net.list_branch_products()
      |> Map.new(&{&1.id, &1})

    ids
    |> Enum.map(&Map.get(products, &1))
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
    |> invalidate_after_success(branch_id)
  end

  def replace_products(staff, branch_id, ids) when is_list(ids) do
    with :ok <- Identity.authorize(staff, "products.update", branch_id),
         true <-
           length(ids) == length(Enum.uniq(ids)) and
             MapSet.subset?(
               MapSet.new(ids),
               MapSet.new(Enum.map(Delivest.Net.list_branch_products(branch_id), & &1.id))
             ) do
      result =
        Repo.transaction(fn ->
          lock_branch(branch_id)
          Repo.delete_all(from e in Entry, where: e.branch_id == ^branch_id)

          Enum.with_index(ids)
          |> Enum.each(fn {id, position} ->
            %Entry{}
            |> Entry.changeset(%{branch_id: branch_id, product_id: id, position: position})
            |> Repo.insert!()
          end)

          get_settings(branch_id)
        end)

      result
      |> Audit.track(staff, "popular.products_replaced")
      |> invalidate_after_success(branch_id)
    else
      false -> {:error, :invalid_products}
      error -> error
    end
  end

  def remove_product(staff, branch_id, product_id) do
    with :ok <- Identity.authorize(staff, "products.update", branch_id) do
      {_count, _} =
        from(e in Entry, where: e.branch_id == ^branch_id and e.product_id == ^product_id)
        |> Repo.delete_all()

      {:ok, :removed}
    end
    |> Audit.track(staff, "popular.product_removed")
    |> invalidate_after_success(branch_id)
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
    |> invalidate_after_success(branch_id)
  end

  defp invalidate_after_success({:ok, _} = result, branch_id) do
    Catalogs.clear_menu_cache(branch_id)
    result
  end

  defp invalidate_after_success(result, _branch_id), do: result

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
