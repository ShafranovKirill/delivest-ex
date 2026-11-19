defmodule Delivest.Storefront do
  @moduledoc "Public, explicitly serialized startup data for the client storefront."
  import Ecto.Query

  alias Delivest.{Franchise, Identity, Repo}
  alias Delivest.Integrations.{Dadata, YandexAds, Zvonok}
  alias Delivest.Franchise.Rating
  alias Delivest.Franchise.SettingsStore
  alias Delivest.Net.{ModifierStop, ProductStop, PublicOffers}
  alias Delivest.Promo.Promotion
  alias Delivest.Storefront.Revisions
  alias Delivest.Storefront.BranchProjection
  alias DelivestWeb.Client.Branch.BranchJSON
  alias DelivestWeb.Client.Franchise.FranchiseJSON
  alias DelivestWeb.Client.Stock.StockJSON
  alias DelivestWeb.Plugs.Locale

  @cache :storefront_cache
  @popular_category_id "00000000-0000-4000-8000-000000000001"
  @popular_label "Popular"
  @cache_max_ms :timer.hours(1)

  def bootstrap(params), do: retry_stale(fn -> do_bootstrap(params) end, 2)

  @sections ~w(franchise branches menu stories advertising)

  def section(name, params) when name in @sections do
    retry_stale(fn -> do_section(name, params) end, 2)
  end

  def section(_name, _params), do: {:error, :unknown_section}

  defp do_section(name, params) do
    locale = normalize_locale(params["locale"])
    branch_id = normalize_id(params["branch_id"])

    cond do
      name in ~w(menu stories advertising) and is_nil(branch_id) ->
        {:error, :invalid_branch}

      Map.has_key?(params, "branch_id") and is_nil(branch_id) ->
        {:error, :invalid_branch}

      true ->
        load_section(name, branch_id, locale)
    end
  end

  defp load_section("franchise", _branch_id, _locale) do
    with {:ok, revision} <- Revisions.current("franchise"),
         {:ok, {:timed, data, boundary}} <- cached({:franchise, revision}, &load_franchise/0),
         :fresh <- if(crossed_boundary?(boundary), do: :stale, else: :fresh),
         true <- Revisions.current("franchise") == {:ok, revision} do
      {:ok, %{data: data, revision: revision, valid_until: valid_until([boundary])}}
    else
      :stale -> {:error, :stale}
      false -> {:error, :stale}
      error -> error
    end
  end

  defp load_section("branches", _branch_id, _locale) do
    with {:ok, revision} <- Revisions.current("branches"),
         {:ok, {:timed, branches, boundary}} <- cached({:branches, revision}, &load_branches/0),
         :fresh <- if(crossed_boundary?(boundary), do: :stale, else: :fresh),
         true <- Revisions.current("branches") == {:ok, revision} do
      {:ok,
       %{
         data: Enum.map(branches.full, &Map.fetch!(branches.details, &1.id)),
         revision: revision,
         valid_until: valid_until([boundary])
       }}
    else
      :stale -> {:error, :stale}
      false -> {:error, :stale}
      error -> error
    end
  end

  defp load_section(name, branch_id, locale) do
    with {:ok, branches_revision} <- Revisions.current("branches"),
         {:ok, {:timed, branches, branch_boundary}} <-
           cached({:branches, branches_revision}, &load_branches/0),
         :active <-
           if(Enum.any?(branches.full, &(&1.id == branch_id)), do: :active, else: :missing),
         {:ok, revision} <- Revisions.current(name, branch_id),
         {:ok, data, boundary} <- section_data(name, branch_id, locale, revision),
         :fresh <-
           if(crossed_boundary?(branch_boundary) or crossed_boundary?(boundary),
             do: :stale,
             else: :fresh
           ),
         true <- Revisions.current("branches") == {:ok, branches_revision},
         true <- Revisions.current(name, branch_id) == {:ok, revision} do
      {:ok,
       %{
         data: data,
         revision: revision,
         valid_until: valid_until([branch_boundary, boundary])
       }}
    else
      :missing -> {:error, :not_found}
      :stale -> {:error, :stale}
      false -> {:error, :stale}
      {:error, :not_found} = error -> error
      error -> error
    end
  end

  defp section_data("menu", branch_id, locale, revision),
    do: maybe_menu(branch_id, locale, revision)

  defp section_data("stories", branch_id, _locale, revision) do
    with {:ok, data} <- maybe_stories(branch_id, revision), do: {:ok, data, nil}
  end

  defp section_data("advertising", branch_id, _locale, revision) do
    with {:ok, data} <- maybe_advertising(branch_id, revision), do: {:ok, data, nil}
  end

  defp do_bootstrap(params) do
    slug = normalize_slug(params["slug"])
    locale = normalize_locale(params["locale"])
    preferred_id = normalize_id(params["branch_id"])

    with {:ok, branches_revision} <- Revisions.current("branches"),
         {:ok, {:timed, branches, branch_boundary}} <-
           cached({:branches, branches_revision}, &load_branches/0) do
      preferred = if preferred_id, do: Enum.find(branches.full, &(&1.id == preferred_id))

      selected =
        cond do
          slug -> Enum.find(branches.full, &(&1.slug == slug))
          preferred -> preferred
          length(branches.full) == 1 -> hd(branches.full)
          true -> nil
        end

      if Map.has_key?(params, "slug") && is_nil(selected) do
        {:error, :not_found}
      else
        assemble(branches, branches_revision, selected, locale, branch_boundary)
      end
    end
  end

  def manifest(branch_id), do: retry_stale(fn -> do_manifest(branch_id) end, 2)

  defp do_manifest(branch_id) do
    with {:ok, uuid} <- Ecto.UUID.cast(branch_id),
         {:ok, branches_revision} <- Revisions.current("branches"),
         {:ok, {:timed, branches, branch_boundary}} <-
           cached({:branches, branches_revision}, &load_branches/0),
         true <- Enum.any?(branches.full, &(&1.id == uuid)),
         {:ok, revisions} <- section_revisions(uuid, branches_revision),
         {:ok, advertising} <-
           cached({:advertising, uuid, revisions.advertising}, fn ->
             YandexAds.public_config(uuid)
           end) do
      result = %{
        revisions: revisions,
        advertising: advertising,
        valid_until: valid_until([branch_boundary])
      }

      if revisions_current?(uuid, revisions), do: {:ok, result}, else: {:error, :stale}
    else
      false -> {:error, :not_found}
      :error -> {:error, :not_found}
      error -> error
    end
  end

  defp retry_stale(fun, attempts) do
    case fun.() do
      {:error, :stale} when attempts > 1 ->
        Revisions.sync()
        retry_stale(fun, attempts - 1)

      result ->
        result
    end
  catch
    :exit, _ -> {:error, :unavailable}
  end

  def watermark(branch_id) do
    with {:ok, manifest} <- manifest(branch_id) do
      {:ok, Map.take(manifest, [:revisions, :valid_until])}
    end
  end

  defp assemble(branches, branches_revision, selected, locale, branch_boundary) do
    branch_id = selected && selected.id

    with {:ok, franchise_revision} <- Revisions.current("franchise"),
         {:ok, {:timed, franchise, franchise_boundary}} <-
           cached({:franchise, franchise_revision}, &load_franchise/0),
         {:ok, revisions} <- section_revisions(branch_id, branches_revision, franchise_revision),
         {:ok, menu, menu_boundary} <- maybe_menu(branch_id, locale, revisions.menu),
         {:ok, stories} <- maybe_stories(branch_id, revisions.stories),
         {:ok, advertising} <- maybe_advertising(branch_id, revisions.advertising) do
      result = %{
        schema_version: 1,
        locale: locale,
        revisions: revisions,
        valid_until: valid_until([franchise_boundary, branch_boundary, menu_boundary]),
        franchise: franchise,
        branches: branches.compact,
        selected_branch: if(selected, do: branches.details[branch_id]),
        menu: menu,
        stories: stories,
        advertising: advertising
      }

      if revisions_current?(branch_id, revisions), do: {:ok, result}, else: {:error, :stale}
    end
  end

  defp maybe_menu(nil, _locale, _revision), do: {:ok, nil, nil}

  defp maybe_menu(branch_id, locale, revision) do
    case cached({:menu, branch_id, locale, revision}, fn ->
           boundary = next_menu_boundary(branch_id)
           if boundary, do: Revisions.schedule_boundary(branch_id, boundary)

           case load_menu(branch_id, locale) do
             {:error, _} = error ->
               error

             data ->
               if crossed_boundary?(boundary),
                 do: {:error, :stale},
                 else: {:timed, data, boundary}
           end
         end) do
      {:ok, {:timed, data, boundary}} -> {:ok, data, boundary}
      error -> error
    end
  end

  defp maybe_stories(nil, _revision), do: {:ok, nil}

  defp maybe_stories(branch_id, revision),
    do: cached({:stories, branch_id, revision}, fn -> load_stories(branch_id) end)

  defp maybe_advertising(nil, _revision), do: {:ok, nil}

  defp maybe_advertising(branch_id, revision),
    do: cached({:advertising, branch_id, revision}, fn -> YandexAds.public_config(branch_id) end)

  defp section_revisions(branch_id, branches_revision \\ nil, franchise_revision \\ nil)

  defp section_revisions(nil, branches_revision, franchise_revision) do
    with {:ok, franchise} <- current_or_value("franchise", franchise_revision) do
      {:ok,
       %{
         franchise: franchise,
         branches: branches_revision,
         menu: nil,
         stories: nil,
         advertising: nil
       }}
    end
  end

  defp section_revisions(branch_id, branches_revision, franchise_revision) do
    with {:ok, franchise} <- current_or_value("franchise", franchise_revision),
         {:ok, branches} <- current_or_value("branches", branches_revision),
         {:ok, menu} <- Revisions.current("menu", branch_id),
         {:ok, stories} <- Revisions.current("stories", branch_id),
         {:ok, advertising} <- Revisions.current("advertising", branch_id) do
      {:ok,
       %{
         franchise: franchise,
         branches: branches,
         menu: menu,
         stories: stories,
         advertising: advertising
       }}
    end
  end

  defp current_or_value(section, nil), do: Revisions.current(section)
  defp current_or_value(_section, value), do: {:ok, value}

  defp revisions_current?(branch_id, expected) do
    current =
      if is_nil(branch_id) do
        with {:ok, branches} <- Revisions.current("branches") do
          section_revisions(nil, branches)
        end
      else
        section_revisions(branch_id)
      end

    case current do
      {:ok, ^expected} -> true
      _ -> false
    end
  end

  defp crossed_boundary?(nil), do: false
  defp crossed_boundary?(boundary), do: DateTime.compare(DateTime.utc_now(), boundary) != :lt

  defp cached(key, loader) do
    result =
      try do
        Cachex.fetch(@cache, key, fn _ ->
          case loader.() do
            {:error, _} = error ->
              {:ignore, error}

            {:timed, _data, boundary} = timed ->
              if fresh_key?(key),
                do: {:commit, timed, expire: ttl_until(boundary)},
                else: {:ignore, {:error, :stale}}

            data ->
              if fresh_key?(key),
                do: {:commit, data, expire: @cache_max_ms},
                else: {:ignore, {:error, :stale}}
          end
        end)
      rescue
        _ -> {:error, :unavailable}
      catch
        :exit, _ -> {:error, :unavailable}
      end

    case result do
      {:ok, {:error, _} = error} -> error
      {:ignore, {:error, _} = error} -> error
      {:ok, value} -> {:ok, value}
      {:commit, value} -> {:ok, value}
      _ -> {:error, :unavailable}
    end
  end

  defp fresh_key?({:franchise, revision}), do: Revisions.db_matches?("franchise", "*", revision)
  defp fresh_key?({:branches, revision}), do: Revisions.db_matches?("branches", "*", revision)

  defp fresh_key?({:menu, branch_id, _locale, revision}),
    do: Revisions.db_matches?("menu", branch_id, revision)

  defp fresh_key?({:stories, branch_id, revision}),
    do: Revisions.db_matches?("stories", branch_id, revision)

  defp fresh_key?({:advertising, branch_id, revision}),
    do: Revisions.db_matches?("advertising", branch_id, revision)

  defp ttl_until(nil), do: @cache_max_ms

  defp ttl_until(boundary) do
    max(1, min(@cache_max_ms, DateTime.diff(boundary, DateTime.utc_now(), :millisecond)))
  end

  defp valid_until(boundaries) do
    now = DateTime.utc_now()
    lease = DateTime.add(now, Revisions.lease_remaining_ms(), :millisecond)

    boundaries
    |> Enum.reject(&is_nil/1)
    |> Enum.reduce(lease, fn boundary, earliest ->
      if DateTime.compare(boundary, earliest) == :lt, do: boundary, else: earliest
    end)
    |> DateTime.to_iso8601()
  end

  defp load_franchise do
    settings = SettingsStore.get_uncached()
    rating = Rating.current(:yandex)
    boundary = if rating, do: DateTime.add(rating.fetched_at, 7, :day), else: nil
    if boundary, do: Revisions.schedule_boundary("franchise", "*", boundary)

    data =
      FranchiseJSON.show(%{
        settings: settings,
        documents: Franchise.list_documents(),
        address_map: Dadata.active?(),
        client_auth: Identity.client_auth_enabled?(),
        client_auth_required: settings.client_auth_required,
        login_call_mode: Zvonok.login_call_mode(),
        rating:
          if(rating,
            do: %{value: rating.rating, count: rating.reviews_count, url: nil},
            else: nil
          )
      }).data

    {:timed, data, boundary}
  end

  defp load_branches do
    full = Identity.list_branches(preload: [:info])

    started_at = DateTime.utc_now()

    boundary =
      full
      |> Enum.flat_map(fn branch ->
        case branch.info do
          %{intake: %{paused_until: paused, load_until: loaded}} -> [paused, loaded]
          _ -> []
        end
      end)
      |> Enum.filter(&(match?(%DateTime{}, &1) and DateTime.compare(&1, started_at) == :gt))
      |> Enum.min_by(&DateTime.to_unix(&1, :millisecond), fn -> nil end)

    if boundary, do: Revisions.schedule_boundary("branches", "*", boundary)

    details =
      full
      |> BranchProjection.prepare()
      |> BranchJSON.index()
      |> Map.fetch!(:data)
      |> Map.new(&{&1.id, &1})

    compact =
      Enum.map(full, fn branch ->
        info = details[branch.id].branch_info

        %{
          id: branch.id,
          slug: branch.slug,
          name: branch.name,
          is_active: true,
          branch_info:
            if(info,
              do:
                Map.take(info, [
                  :address,
                  :city,
                  :manual_rating,
                  :latitude,
                  :longitude,
                  :timezone,
                  :working_hours,
                  :special_hours,
                  :intake,
                  :fulfillment_methods
                ]),
              else: nil
            )
        }
      end)

    if crossed_boundary?(boundary) do
      {:error, :stale}
    else
      {:timed,
       %{full: Enum.map(full, &Map.take(&1, [:id, :slug])), details: details, compact: compact},
       boundary}
    end
  end

  defp load_menu(branch_id, locale) do
    case PublicOffers.menu_fresh(branch_id) do
      {:ok, categories} ->
        Gettext.with_locale(DelivestWeb.Gettext, locale, fn ->
          categories
          |> Enum.map(fn
            %{id: @popular_category_id} = category ->
              %{category | name: Gettext.gettext(DelivestWeb.Gettext, @popular_label)}

            category ->
              category
          end)
          |> then(&DelivestWeb.Client.Menu.MenuJSON.index(%{menu: &1, prepared: true}).data)
        end)

      _ ->
        {:error, :unavailable}
    end
  end

  defp next_menu_boundary(branch_id) do
    now = DateTime.utc_now()

    stops =
      Repo.all(
        from s in ProductStop,
          where: s.branch_id == ^branch_id and s.until > ^now,
          select: s.until
      )

    modifiers =
      Repo.all(
        from s in ModifierStop,
          where: s.branch_id == ^branch_id and s.until > ^now,
          select: s.until
      )

    promotions =
      Repo.all(
        from p in Promotion,
          where: p.branch_id == ^branch_id and p.enabled and is_nil(p.deleted_at),
          select: {p.starts_at, p.ends_at}
      )

    (stops ++ modifiers ++ Enum.flat_map(promotions, fn {start, finish} -> [start, finish] end))
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(&(DateTime.compare(&1, now) == :gt))
    |> Enum.min_by(&DateTime.to_unix(&1, :millisecond), fn -> nil end)
  end

  defp load_stories(branch_id),
    do:
      StockJSON.index(%{stocks: Delivest.Net.Stocks.list_stocks_uncached_for_branch(branch_id)}).data

  defp normalize_slug(value) when is_binary(value) and byte_size(value) in 1..128,
    do: String.trim(value)

  defp normalize_slug(_), do: nil

  defp normalize_id(value) when is_binary(value) do
    case Ecto.UUID.cast(value) do
      {:ok, id} -> id
      _ -> nil
    end
  end

  defp normalize_id(_), do: nil

  defp normalize_locale(locale) when locale in ["ru", "en"], do: locale
  defp normalize_locale(_), do: Locale.default_locale()
end
