defmodule Delivest.Analytics.Reports do
  @moduledoc "Authorized read model over published daily analytics buckets."
  alias Delivest.{Background, Features, Identity, Repo}
  alias Delivest.Analytics.Reports.Query

  @feature_by_tab %{
    "funnel" => "analytics_funnel",
    "sources" => "analytics_links",
    "customers" => "analytics_extended",
    "channels" => "analytics_extended",
    "comparison" => "analytics_extended",
    "franchise" => "analytics_franchise"
  }

  @kind_by_feature %{
    "analytics_funnel" => "analytics.funnel",
    "analytics_links" => "analytics.links",
    "analytics_extended" => "analytics.extended"
  }

  def feature_for_tab(tab), do: Map.get(@feature_by_tab, tab)

  def read(staff, scope, period, tab, filters \\ %{})

  def read(staff, {:branch, branch_id}, {from, to}, tab, filters) do
    feature = feature_for_tab(tab)

    with true <- feature != nil and tab != "franchise",
         :ok <- Identity.authorize(staff, "statistics.read", branch_id),
         true <- Features.enabled?(feature, {:branch, branch_id}),
         :ok <- valid_period(from, to) do
      report = present(feature, [branch_id], {from, to}, tab, filters)
      job = Background.calculation_status(@kind_by_feature[feature], {:branch, branch_id})
      {:ok, Map.put(report, :job, job)}
    else
      _ -> {:error, :forbidden}
    end
  end

  def read(staff, :franchise, {from, to}, "franchise", filters) do
    with true <-
           Identity.can?(staff, "statistics.read") and Identity.can?(staff, "statistics.network"),
         true <- Features.enabled?("analytics_franchise", :franchise),
         :ok <- valid_period(from, to) do
      all_ids =
        staff
        |> Identity.list_branch_for_staff()
        |> Enum.map(& &1.id)
        |> restrict_branches(filters)

      enabled = Features.enabled_branches("analytics_franchise", all_ids)
      ids = Enum.filter(all_ids, &MapSet.member?(enabled, &1))
      report = present("analytics_extended", ids, {from, to}, "franchise", filters)

      excluded = length(all_ids) - MapSet.size(enabled)
      state = if excluded > 0 and report.state != :not_collected, do: :partial, else: report.state
      {:ok, %{report | excluded_branches: excluded, state: state} |> Map.put(:job, nil)}
    else
      _ -> {:error, :forbidden}
    end
  end

  def read(_, _, _, _, _), do: {:error, :forbidden}

  def request_rebuild(staff, feature, branch_id, {from, to}) do
    with true <- Identity.can?(staff, "admin"),
         true <- feature in Map.keys(@kind_by_feature),
         :ok <- Identity.authorize(staff, "statistics.read", branch_id),
         {:ok, token} <- Features.snapshot(feature, {:branch, branch_id}),
         :ok <- valid_period(from, to),
         true <- feature != "analytics_funnel" or Date.diff(Date.utc_today(), from) <= 90 do
      Features.with_enabled(feature, {:branch, branch_id}, token, fn ->
        Repo.query!(
          """
          INSERT INTO analytics_report_states(feature,branch_id,day,revision,inserted_at,updated_at)
          SELECT $1,$2::text::uuid,d::date,1,timezone('UTC', now()),timezone('UTC', now())
          FROM generate_series($3::date,$4::date,interval '1 day') d
          ON CONFLICT (feature,branch_id,day)
          DO UPDATE SET revision=analytics_report_states.revision+1,updated_at=timezone('UTC', now())
          """,
          [feature, branch_id, from, to]
        )
      end)
      |> case do
        {:ok, _} ->
          Background.run_now(@kind_by_feature[feature], {:branch, branch_id}, new_work: true)

        other ->
          other
      end
    else
      _ -> {:error, :forbidden}
    end
  end

  defp valid_period(%Date{} = from, %Date{} = to) do
    if Date.compare(from, to) != :gt and Date.diff(to, from) < 367,
      do: :ok,
      else: {:error, :invalid_period}
  end

  defp valid_period(_, _), do: {:error, :invalid_period}

  defp restrict_branches(ids, %{"branch_ids" => selected}) when is_list(selected),
    do: Enum.filter(ids, &(&1 in selected))

  defp restrict_branches(ids, %{"branch_id" => selected})
       when is_binary(selected) and selected != "",
       do: Enum.filter(ids, &(&1 == selected))

  defp restrict_branches(ids, _), do: ids

  defp present(feature, ids, {from, to}, tab, filters) do
    page = page(filters)
    data = Query.read(feature, ids, from, to, tab, filters, page)
    coverage = data.coverage
    expected = length(ids) * (Date.diff(to, from) + 1)

    %{
      tab: tab,
      feature: feature,
      state:
        state(
          coverage.days,
          expected,
          data.total_rows,
          coverage.asof,
          feature,
          to,
          coverage.dirty
        ),
      covered_days: coverage.days,
      expected_days: expected,
      last_success_at: coverage.asof,
      rows: label_links(data.rows, tab),
      total_rows: data.total_rows,
      page: page,
      pages: max(ceil(data.total_rows / Query.page_size()), 1),
      totals: data.totals,
      branch_rows: data.branch_rows,
      verified_buyers: if(coverage.days == 0, do: nil, else: data.verified_buyers),
      repeat_buyers: if(coverage.days == 0, do: nil, else: data.repeat_buyers),
      retention: data.retention,
      excluded_branches: 0
    }
  end

  defp page(%{"page" => raw}) when is_binary(raw) do
    case Integer.parse(raw) do
      {value, ""} -> value |> max(1) |> min(10_000)
      _ -> 1
    end
  end

  defp page(_), do: 1

  defp label_links(rows, "sources") when rows != [] do
    ids = Enum.map(rows, &Ecto.UUID.dump!(&1.key))

    labels =
      Repo.query!(
        "SELECT id::text,name,campaign FROM advertising_links WHERE id=ANY($1::uuid[])",
        [ids]
      ).rows
      |> Map.new(fn [id, name, campaign] -> {id, "#{name} · #{campaign}"} end)

    Enum.map(rows, &Map.put(&1, :label, Map.get(labels, &1.key, &1.key)))
  end

  defp label_links(rows, _), do: rows

  defp state(0, _expected, _count, _asof, _feature, _to, _dirty), do: :not_collected

  defp state(covered, expected, _count, _asof, _feature, _to, _dirty) when covered < expected,
    do: :partial

  defp state(_, _, _, _, _, _, true), do: :stale
  defp state(_, _, 0, _, _, _, false), do: :empty

  defp state(_, _, _, asof, feature, to, false) do
    age = if asof, do: DateTime.diff(DateTime.utc_now(), asof), else: 0
    threshold = if feature in ["analytics_funnel", "analytics_links"], do: 1800, else: 172_800

    if Date.compare(to, Date.utc_today()) != :lt and age > threshold,
      do: :stale,
      else: :ready
  end
end
