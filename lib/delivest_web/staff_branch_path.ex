defmodule DelivestWeb.StaffBranchPath do
  @moduledoc "Allowlisted staff scope transitions. Paths in a URL never grant branch access."
  use Gettext, backend: DelivestWeb.Gettext

  @branch_lists ~w(
    dashboard statistics analytics/channels analytics/sources analytics/funnel analytics/customers orders deliveries couriers delivery delivery/address delivery/zones
    delivery/couriers finance/payments finance/transactions finance/receipts finance/printing integrations integrations/frontpad
    integrations/ycart integrations/vk-ads integrations/iiko integrations/rkeeper integrations/routes
    integrations/zvonok integrations/dadata integrations/yookassa integrations/yandex-eda
    integrations/yandex-delivery integrations/fiscal categories products products/bulk
    products/operations products/stops products/modifiers products/suggested products/tags
    menu/popular stocks loyalty promotions advertising-links pos kitchen
  )
  @network_routes ~w(
    dashboard statistics analytics/channels analytics/sources analytics/funnel analytics/customers
    analytics/comparison analytics/advertising integrations integrations/zvonok integrations/dadata integrations/yookassa
    integrations/yandex-eda settings franchise branches employee roles clients segments marketing marketing/bonuses
    marketing/policies diagnostics logs logs/raw logs/errors
  )
  @counterparts %{
    "dashboard" => "dashboard",
    "statistics" => "statistics",
    "analytics/channels" => "analytics/channels",
    "analytics/sources" => "analytics/sources",
    "analytics/funnel" => "analytics/funnel",
    "analytics/customers" => "analytics/customers",
    "integrations" => "integrations"
  }
  @data_settings_paths ~w(/staff/settings/data-transfer /staff/settings/data-system)
  @analytics_routes ~w(statistics analytics/channels analytics/sources analytics/funnel analytics/customers analytics/comparison analytics/advertising)
  @choosable_analytics_routes ~w(statistics analytics/channels analytics/sources analytics/funnel analytics/customers)
  @creation_routes ~w(
    orders/new products/new products/tags/new categories/new promotions/new promotions/new/full
    promotions/new/first-order promotions/sale stocks/new
  )
  @filters %{
    "products" => ~w(search is_active page_size order_by order_directions[]),
    "orders" =>
      ~w(status search period problem sort date_from date_to receiving payment source page_size),
    "statistics" =>
      ~w(tab period from to channel sort compare compare_from compare_to granularity),
    "analytics/channels" => ~w(period from to channel page),
    "analytics/sources" => ~w(period from to channel page),
    "analytics/funnel" => ~w(period from to channel page),
    "analytics/customers" => ~w(period from to channel page),
    "analytics/comparison" => ~w(period from to channel page),
    "analytics/advertising" => ~w(period from to channel page),
    "deliveries" => ~w(status search),
    "couriers" => ~w(status search),
    "promotions" => ~w(search status),
    "stocks" => ~w(search status),
    "categories" => ~w(search),
    "finance/receipts" => ~w(status search from to page_size),
    "finance/transactions" => ~w(status search from to page_size)
  }

  def home(nil), do: "/staff"
  def home(branch), do: "/staff/b/#{branch.slug}/dashboard"

  def strip(path) when is_binary(path), do: String.replace(path, ~r{^/staff/b/[^/]+}, "/staff")
  def strip(path), do: path

  @doc "Returns a destination and visible label, or an explicit fallback/choice."
  def transition(source, target) when is_binary(source) do
    with {:ok, route, query} <- classify(source),
         {:ok, target_path, mode} <- destination(route, target) do
      result = %{path: target_path <> compatible_query(route, query), label: label(mode)}

      case mode do
        :direct ->
          {:ok, result}

        :branch_overview ->
          {:fallback, Map.put(result, :reason, :no_branch_counterpart)}

        :network_overview ->
          {:choice, %{stay: source, overview: result.path, label: result.label}}
      end
    else
      _ -> :error
    end
  end

  def transition(_, _), do: :error

  @doc "A branch-scoped navigation target opens an explicit branch chooser from network scope."
  def contextual_navigation_path(path, scope_branch, return_source) do
    parsed_path = if is_binary(path), do: URI.parse(path).path

    cond do
      parsed_path == "/staff/settings" and is_binary(return_source) and
          URI.parse(return_source).path == "/staff/settings" ->
        settings_source_path(return_source)

      analytics_target?(path) ->
        if analytics_target?(return_source) or not choosable_analytics_target?(path) do
          analytics_period_path(path, return_source)
        else
          selection_path(path, return_source) || path
        end

      parsed_path in @data_settings_paths ->
        case scope_branch do
          %{slug: slug} -> scoped_settings_path(parsed_path, slug)
          _ -> scoped_settings_path(parsed_path, nil)
        end

      is_nil(scope_branch) ->
        selection_path(path, return_source) || path

      true ->
        path
    end
  end

  defp settings_source_path(source) do
    case classify(source) do
      {:ok, {:settings_summary, branch}, _query} -> settings_path(branch)
      _ -> "/staff/settings"
    end
  end

  defp analytics_target?(path) when is_binary(path) do
    case classify(path) do
      {:ok, {:branch, _, route}, _} -> route in @analytics_routes
      {:ok, {:network, route}, _} -> route in @analytics_routes
      _ -> false
    end
  end

  defp analytics_target?(_), do: false

  defp choosable_analytics_target?(path) when is_binary(path) do
    case classify(path) do
      {:ok, {:branch, _, route}, _} -> route in @choosable_analytics_routes
      {:ok, {:network, route}, _} -> route in @choosable_analytics_routes
      _ -> false
    end
  end

  defp choosable_analytics_target?(_), do: false

  defp analytics_period_path(path, source) when is_binary(source) do
    case classify(source) do
      {:ok, {:branch, _slug, route}, query} ->
        if route in @analytics_routes, do: merge_period(path, query), else: path

      {:ok, {:network, route}, query} ->
        if route in @analytics_routes, do: merge_period(path, query), else: path

      _ ->
        path
    end
  end

  defp analytics_period_path(path, _source), do: path

  defp merge_period(path, source_query) do
    uri = URI.parse(path)

    query =
      Map.merge(Map.take(source_query, ~w(period from to)), URI.decode_query(uri.query || ""))

    URI.to_string(%{
      uri
      | query: if(map_size(query) == 0, do: nil, else: URI.encode_query(query))
    })
  end

  def selection_path(target_path, return_source) do
    case selection_intent(target_path, return_source) do
      {:ok, %{source: source, return_to: return_to}} ->
        "/staff/branches/select?" <>
          URI.encode_query(%{"from" => source, "return_to" => return_to})

      :error ->
        nil
    end
  end

  def selection_destination(source, target_slug) when is_binary(target_slug) do
    with {:ok, canonical} <- selection_source(source),
         true <- valid_slug?(target_slug) do
      case creation_route(canonical) do
        nil ->
          case transition(canonical, {:branch, target_slug}) do
            {:ok, %{path: path}} -> {:ok, path}
            _ -> :error
          end

        route ->
          {:ok, "/staff/b/#{target_slug}/#{route}"}
      end
    else
      _ -> :error
    end
  end

  def selection_destination(_, _), do: :error

  def selection_intent(target_path, return_source) do
    with {:ok, source} <- selection_source(target_path) do
      return_to =
        if choosable_analytics_target?(source),
          do: safe_analytics_return(return_source),
          else: safe_network_return(return_source)

      {:ok, %{source: source, return_to: return_to}}
    end
  end

  @doc "Optional report tab for branch feature filtering on the selection page."
  def selection_report_section(source) when is_binary(source) do
    case classify(source) do
      {:ok, {:branch, _, "analytics/" <> tab}, _}
      when tab in ~w(channels sources funnel customers) ->
        tab

      {:ok, {:network, "analytics/" <> tab}, _}
      when tab in ~w(channels sources funnel customers) ->
        tab

      _ ->
        nil
    end
  end

  def selection_report_section(_), do: nil

  defp selection_source(source) when is_binary(source) do
    case classify(source) do
      {:ok, {:branch, slug, route}, _query} ->
        cond do
          shared_integration?(route) -> :error
          creation_route(source) -> {:ok, URI.parse(source).path}
          true -> canonical_branch_source(source, slug)
        end

      {:ok, {:branch_settings, slug, _section}, _query} ->
        canonical_branch_source(source, slug)

      {:ok, {:network, route}, _query} when route in @choosable_analytics_routes ->
        case transition(source, :network) do
          {:ok, %{path: path}} -> {:ok, path}
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp selection_source(_), do: :error

  defp creation_route(source) do
    case URI.parse(source).path do
      path when is_binary(path) ->
        case Regex.run(~r{^/staff/b/[a-z0-9-]+/(.+)$}, path) do
          [_, route] when route in @creation_routes -> route
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp canonical_branch_source(source, slug) do
    case transition(source, {:branch, slug}) do
      {:ok, %{path: path}} -> {:ok, path}
      _ -> :error
    end
  end

  defp safe_network_return(source) when is_binary(source) do
    case classify(source) do
      {:ok, {:network, _route}, _query} -> network_return(source)
      {:ok, {:settings_summary, _slug}, _query} -> network_return(source)
      {:ok, {:data_transfer, _slug}, _query} -> network_return(source)
      {:ok, {:data_system, _slug}, _query} -> network_return(source)
      _ -> "/staff/dashboard"
    end
  end

  defp safe_network_return(_), do: "/staff/dashboard"

  defp safe_analytics_return(source) when is_binary(source) do
    case classify(source) do
      {:ok, {:branch, slug, _route}, _query} ->
        case canonical_branch_source(source, slug) do
          {:ok, path} -> path
          :error -> "/staff/dashboard"
        end

      _ ->
        safe_network_return(source)
    end
  end

  defp safe_analytics_return(_), do: "/staff/dashboard"

  defp network_return(source) do
    case transition(source, :network) do
      {:ok, %{path: path}} -> path
      _ -> "/staff/dashboard"
    end
  end

  @doc "Canonical branch section for legacy links; unknown and object routes are rejected."
  def section(path) when is_binary(path) do
    case classify(path) do
      {:ok, {:branch, _slug, route}, _query} -> "/" <> route
      _ -> nil
    end
  end

  def section(_), do: nil

  def valid_section?("/" <> section), do: section in @branch_lists
  def valid_section?(_), do: false

  defp classify(source) do
    uri = URI.parse(source)
    path = uri.path || ""
    query = URI.decode_query(uri.query || "")

    cond do
      uri.host || uri.scheme || not String.starts_with?(path, "/staff/") ||
        Regex.match?(~r/%(?![0-9a-fA-F]{2})/, source) ||
          Regex.match?(~r/[\x00-\x1F]/, source) ->
        :error

      match = Regex.run(~r{^/staff/b/([a-z0-9-]+)/(.+)$}, path) ->
        [_, slug, rest] = match
        classify_branch(slug, rest, query)

      match = Regex.run(~r{^/staff/branches/([a-z0-9-]+)/edit(?:/([a-z-]+))?$}, path) ->
        [_, slug | section] = match
        section = List.first(section)

        if section in [nil, "" | branch_setting_sections()],
          do: {:ok, {:branch_settings, slug, section}, query},
          else: :error

      path in @data_settings_paths ->
        branch = query["branch"]
        branch = if is_binary(branch) and valid_slug?(branch), do: branch, else: nil
        kind = if path == "/staff/settings/data-transfer", do: :data_transfer, else: :data_system
        {:ok, {kind, branch}, %{}}

      path == "/staff/settings" ->
        branch = query["branch"]
        branch = if is_binary(branch) and valid_slug?(branch), do: branch, else: nil
        {:ok, {:settings_summary, branch}, %{}}

      true ->
        classify_network(path, query)
    end
  rescue
    _ -> :error
  end

  defp classify_branch(slug, route, query) do
    cond do
      route in @branch_lists ->
        {:ok, {:branch, slug, route}, query}

      Regex.match?(~r{^orders/[^/]+(?:/edit)?$}, route) ->
        {:ok, {:branch, slug, "orders"}, %{}}

      Regex.match?(~r{^products/[^/]+(?:/edit)?$}, route) ->
        {:ok, {:branch, slug, "products"}, %{}}

      Regex.match?(~r{^products/tags/[^/]+/edit$}, route) ->
        {:ok, {:branch, slug, "products/tags"}, %{}}

      Regex.match?(~r{^categories/[^/]+(?:/edit|/products)?$}, route) ->
        {:ok, {:branch, slug, "categories"}, %{}}

      Regex.match?(~r{^promotions/[^/]+(?:/edit|/codes)?$}, route) ->
        {:ok, {:branch, slug, "promotions"}, %{}}

      Regex.match?(~r{^stocks/[^/]+/edit$}, route) ->
        {:ok, {:branch, slug, "stocks"}, %{}}

      route in ~w(orders/new products/new promotions/new promotions/new/full promotions/new/first-order promotions/sale stocks/new categories/new) ->
        {:ok, {:branch, slug, String.split(route, "/") |> hd()}, %{}}

      route == "products/tags/new" ->
        {:ok, {:branch, slug, "products/tags"}, %{}}

      true ->
        :error
    end
  end

  defp classify_network(path, query) do
    rest = String.trim_leading(path, "/staff/")

    cond do
      rest in @network_routes || franchise_section?(rest) ->
        {:ok, {:network, rest}, query}

      Regex.match?(~r{^(clients|segments|employee|roles)/[^/]+(?:/edit)?$}, rest) ->
        {:ok, {:network, String.split(rest, "/") |> hd()}, %{}}

      rest in ~w(clients/new segments/new employee/new roles/new) ->
        {:ok, {:network, String.split(rest, "/") |> hd()}, %{}}

      true ->
        :error
    end
  end

  defp destination({:branch, _slug, route}, {:branch, target_slug})
       when is_binary(target_slug) do
    cond do
      not valid_slug?(target_slug) -> :error
      shared_integration?(route) -> {:ok, "/staff/#{route}", :direct}
      true -> {:ok, "/staff/b/#{target_slug}/#{route}", :direct}
    end
  end

  defp destination({:branch_settings, _slug, section}, {:branch, target_slug})
       when is_binary(target_slug) do
    if valid_slug?(target_slug) do
      suffix = if section in [nil, ""], do: "", else: "/#{section}"
      {:ok, "/staff/branches/#{target_slug}/edit#{suffix}", :direct}
    else
      :error
    end
  end

  defp destination({:network, route}, {:branch, target_slug}) when is_binary(target_slug) do
    cond do
      not valid_slug?(target_slug) ->
        :error

      shared_integration?(route) ->
        {:ok, "/staff/#{route}", :direct}

      counterpart = @counterparts[route] ->
        {:ok, "/staff/b/#{target_slug}/#{counterpart}", :direct}

      true ->
        {:ok, "/staff/b/#{target_slug}/dashboard", :branch_overview}
    end
  end

  defp destination({:branch, _slug, route}, :network) do
    cond do
      shared_integration?(route) -> {:ok, "/staff/#{route}", :direct}
      counterpart = @counterparts[route] -> {:ok, "/staff/#{counterpart}", :direct}
      true -> {:ok, "/staff/dashboard", :network_overview}
    end
  end

  defp destination({:branch_settings, _slug, _section}, :network),
    do: {:ok, "/staff/dashboard", :network_overview}

  defp destination({:settings_summary, _source_slug}, {:branch, target_slug})
       when is_binary(target_slug) do
    if valid_slug?(target_slug),
      do: {:ok, settings_path(target_slug), :direct},
      else: :error
  end

  defp destination({:settings_summary, _source_slug}, :network),
    do: {:ok, settings_path(nil), :direct}

  defp destination({kind, _source_slug}, {:branch, target_slug})
       when kind in [:data_transfer, :data_system] and is_binary(target_slug) do
    if valid_slug?(target_slug),
      do: {:ok, scoped_settings_path(data_settings_path(kind), target_slug), :direct},
      else: :error
  end

  defp destination({kind, _source_slug}, :network)
       when kind in [:data_transfer, :data_system],
       do: {:ok, data_settings_path(kind), :direct}

  defp destination({:network, route}, :network), do: {:ok, "/staff/#{route}", :direct}
  defp destination(_, _), do: :error

  defp compatible_query({:branch, _slug, route}, query) do
    keys = Map.get(@filters, route, [])
    encode_query(query, keys)
  end

  defp compatible_query({:network, route}, query) do
    keys = Map.get(@filters, route, [])
    encode_query(query, keys)
  end

  defp compatible_query(_, _), do: ""

  defp encode_query(query, keys) do
    allowed = Map.take(query, keys)
    if map_size(allowed) == 0, do: "", else: "?" <> URI.encode_query(allowed)
  end

  defp settings_path(nil), do: "/staff/settings"
  defp settings_path(branch), do: "/staff/settings?" <> URI.encode_query(%{"branch" => branch})

  defp data_settings_path(:data_transfer), do: "/staff/settings/data-transfer"
  defp data_settings_path(:data_system), do: "/staff/settings/data-system"
  defp scoped_settings_path(path, nil), do: path
  defp scoped_settings_path(path, slug), do: "#{path}?branch=#{slug}"

  defp valid_slug?(slug), do: Regex.match?(~r/^[a-z0-9-]+$/, slug)

  defp branch_setting_sections,
    do: Enum.map(DelivestWeb.Staff.BranchLive.Sections.all(), &Atom.to_string(&1.id))

  defp franchise_section?("franchise/" <> section),
    do:
      Enum.any?(
        DelivestWeb.Staff.FranchiseLive.Sections.all(),
        &(Atom.to_string(&1.id) == section)
      )

  defp franchise_section?(_), do: false

  defp shared_integration?(route),
    do:
      route in ~w(integrations/zvonok integrations/dadata integrations/yookassa integrations/yandex-eda)

  defp label(:direct), do: nil
  defp label(:branch_overview), do: gettext("Branch overview")
  defp label(:network_overview), do: gettext("Network overview")
end
