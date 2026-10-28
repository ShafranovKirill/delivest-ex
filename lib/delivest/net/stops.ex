defmodule Delivest.Net.Stops do
  import Ecto.Query

  alias Delivest.{Audit, Identity, Repo}
  alias Delivest.Integrations.Channels
  alias Delivest.Net.{Product, ProductStop, StopPeriod}

  @cache :stop_cache
  @ttl :timer.seconds(60)

  def stopped_ids(branch_id, now \\ DateTime.utc_now()) do
    for stop <- cached(branch_id),
        StopPeriod.active?(stop, now),
        into: MapSet.new(),
        do: stop.product_id
  end

  def stopped?(branch_id, product_id, now \\ DateTime.utc_now()),
    do: branch_id |> stopped_ids(now) |> MapSet.member?(product_id)

  def ensure_available(branch_id, product_ids) do
    if MapSet.disjoint?(stopped_ids(branch_id), MapSet.new(product_ids)),
      do: {:ok, :available},
      else: {:error, :product_unavailable}
  end

  def by_product(branch_id, now \\ DateTime.utc_now()) do
    branch_id
    |> active_query(now)
    |> preload(:staff)
    |> Repo.all()
    |> Enum.group_by(& &1.product_id)
  end

  def stop(staff, branch_id, %Product{} = product, period)
      when period in [:today, :until_resumed] do
    if Identity.authorize(staff, "stops.update", branch_id) == :ok do
      with {:ok, stop} <- insert_manual(staff, branch_id, product, period) do
        changed(branch_id)

        Audit.record(staff, "product.stopped", product,
          branch_id: branch_id,
          metadata: %{until: stop.until}
        )

        {:ok, stop}
      end
    else
      {:error, :forbidden}
    end
  end

  defp insert_manual(staff, branch_id, product, period) do
    %ProductStop{
      product_id: product.id,
      branch_id: branch_id,
      source: ProductStop.manual(),
      until: StopPeriod.until(period, DateTime.utc_now()),
      staff_id: staff.id
    }
    |> Repo.insert(
      on_conflict: {:replace, [:until, :staff_id, :updated_at]},
      conflict_target: [:product_id, :source],
      returning: true
    )
  end

  def resume(staff, branch_id, %Product{} = product) do
    if Identity.authorize(staff, "stops.update", branch_id) == :ok do
      from(s in ProductStop,
        where: s.product_id == ^product.id and s.source == ^ProductStop.manual()
      )
      |> Repo.delete_all()

      changed(branch_id)
      Audit.record(staff, "product.resumed", product, branch_id: branch_id)
      {:ok, product}
    else
      {:error, :forbidden}
    end
  end

  def replace_external(branch_id, source, product_ids) do
    product_ids = MapSet.new(product_ids)

    current =
      branch_id |> source_query(source) |> select([s], s.product_id) |> Repo.all() |> MapSet.new()

    added = MapSet.difference(product_ids, current)
    removed = MapSet.difference(current, product_ids)

    Repo.transaction(fn ->
      branch_id
      |> source_query(source)
      |> where([s], s.product_id in ^MapSet.to_list(removed))
      |> Repo.delete_all()

      Repo.insert_all(ProductStop, Enum.map(added, &external_row(branch_id, source, &1)),
        on_conflict: :nothing,
        conflict_target: [:product_id, :source]
      )
    end)

    changed? = MapSet.size(added) + MapSet.size(removed) > 0
    if changed?, do: changed(branch_id)
    {:ok, changed?}
  end

  defp external_row(branch_id, source, product_id) do
    now = DateTime.utc_now(:second)

    %{
      id: Ecto.UUID.generate(),
      product_id: product_id,
      branch_id: branch_id,
      source: to_string(source),
      inserted_at: now,
      updated_at: now
    }
  end

  defp active_query(branch_id, now) do
    from(s in ProductStop,
      where: s.branch_id == ^branch_id and (is_nil(s.until) or s.until > ^now)
    )
  end

  defp source_query(branch_id, source) do
    from(s in ProductStop, where: s.branch_id == ^branch_id and s.source == ^to_string(source))
  end

  defp cached(branch_id) do
    case Cachex.fetch(@cache, branch_id, &{:commit, load(&1), ttl: @ttl}) do
      {:ok, stops} -> stops
      {:commit, stops} -> stops
      {:commit, stops, _opts} -> stops
      {:error, _reason} -> load(branch_id)
    end
  end

  defp load(branch_id) do
    from(s in ProductStop,
      where: s.branch_id == ^branch_id,
      select: %{product_id: s.product_id, until: s.until}
    )
    |> Repo.all()
  end

  defp changed(branch_id) do
    Cachex.del(@cache, branch_id)
    Phoenix.PubSub.broadcast(Delivest.PubSub, "branch_products:#{branch_id}", :stops_changed)
    Channels.stops_changed(branch_id)
  end
end
