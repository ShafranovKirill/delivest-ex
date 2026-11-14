defmodule DelivestWeb.StaffBranchPath do
  @moduledoc "Allowlisted staff scope transitions. Paths in a URL never grant branch access."
  use Gettext, backend: DelivestWeb.Gettext

  @branch_lists ~w(
    dashboard statistics orders deliveries couriers delivery delivery/address delivery/zones
    delivery/couriers finance/payments finance/transactions finance/receipts integrations integrations/frontpad
    integrations/ycart integrations/iiko integrations/rkeeper integrations/routes
    integrations/zvonok integrations/dadata integrations/yookassa integrations/yandex-eda
    integrations/yandex-delivery integrations/fiscal categories products products/bulk
    products/operations products/stops products/modifiers products/suggested products/tags
    menu/popular stocks loyalty promotions advertising-links pos kitchen
  )
  @network_routes ~w(
    dashboard statistics integrations integrations/zvonok integrations/dadata integrations/yookassa
    integrations/yandex-eda settings franchise branches employee roles clients segments marketing marketing/bonuses
    marketing/policies diagnostics logs logs/raw logs/errors
  )
  @counterparts %{
    "dashboard" => "dashboard",
    "statistics" => "statistics",
    "integrations" => "integrations"
  }
  @settings_filters ~w(all enabled disabled attention)
  @creation_routes ~w(
    orders/new products/new products/tags/new categories/new promotions/new promotions/new/full
    promotions/new/first-order promotions/sale stocks/new
  )
  @filters %{
    "products" => ~w(search is_active page_size order_by order_directions[]),
    "orders" =>
      ~w(status search period problem sort date_from date_to receiving payment source page_size),
    "statistics" => ~w(tab period channel),
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
  def contextual_navigation_path(path, nil, return_source),
    do: selection_path(path, return_source) || path

  def contextual_navigation_path(path, _scope_branch, _return_source), do: path

  def selection_path(target_path, return_source) do
    case selection_intent(target_path, return_source) do
      {:ok, %{source: source, return_to: return_to}} ->
        "/staff/branches/select?" <>
          URI.encode_query(%{"modal" => "true", "from" => source, "return_to" => return_to})

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
      {:ok, %{source: source, return_to: safe_network_return(return_source)}}
    end
  end

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
      {:ok, {:settings_summary, _slug, _filter}, _query} -> network_return(source)
      _ -> "/staff/dashboard"
    end
  end

  defp safe_network_return(_), do: "/staff/dashboard"

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

      path == "/staff/settings" ->
        branch = query["branch"]
        branch = if is_binary(branch) and valid_slug?(branch), do: branch, else: nil
        filter = if query["filter"] in @settings_filters, do: query["filter"], else: nil
        {:ok, {:settings_summary, branch, filter}, %{}}

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

  defp destination({:settings_summary, _source_slug, filter}, {:branch, target_slug})
       when is_binary(target_slug) do
    if valid_slug?(target_slug),
      do: {:ok, settings_path(target_slug, filter), :direct},
      else: :error
  end

  defp destination({:settings_summary, _source_slug, filter}, :network),
    do: {:ok, settings_path(nil, filter), :direct}

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

  defp settings_path(branch, filter) do
    params = %{}
    params = if branch, do: Map.put(params, "branch", branch), else: params
    params = if filter, do: Map.put(params, "filter", filter), else: params

    if map_size(params) == 0,
      do: "/staff/settings",
      else: "/staff/settings?" <> URI.encode_query(params)
  end

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
