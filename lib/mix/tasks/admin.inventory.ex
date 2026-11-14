defmodule Mix.Tasks.Admin.Inventory do
  use Mix.Task

  @shortdoc "Generate or check the source-based staff administration inventory"
  @snapshot "docs/admin/inventory.json"
  @summary "docs/admin/inventory.md"
  @staff "lib/delivest_web/live/staff"
  @poller_keys %{
    "yandex_delivery" => "Delivest.Integrations.YandexDelivery.Poller",
    "crm_stops" => "Delivest.Integrations.Crm.StopPoller",
    "crm_catalog" => "Delivest.Integrations.Crm.CatalogPoller",
    "crm_silence" => "Delivest.Integrations.Crm.SilencePoller",
    "rkeeper" => "Delivest.Integrations.Rkeeper.Poller",
    "yandex_eda_busy" => "Delivest.Integrations.YandexEda.BusyPoller",
    "atol_kkt" => "Delivest.Integrations.AtolOnline.KktPoller",
    "dadata" => "Delivest.Integrations.Dadata.Poller",
    "yookassa_reconcile" => "Delivest.Integrations.Yookassa.Reconciliation",
    "yandex_rating" => "Delivest.Integrations.YandexRating.Poller"
  }
  @integration_semantics %{
    "atol_online" =>
      {"branch: branch_info.fiscal.atol", "fiscal mode :own",
       "Delivest.Fiscal.BranchSettings.own?/1"},
    "dadata" =>
      {"network: dadata_settings", "settings.enabled",
       "Delivest.Integrations.Dadata.Settings.active?/1"},
    "frontpad" =>
      {"branch: branch_info.crm.frontpad", "crm.enabled and provider :frontpad",
       "Delivest.Integrations.Crm.BranchSettings.active_provider/1; Frontpad.configured?/1"},
    "iiko" =>
      {"branch: branch_info.crm.iiko", "crm.enabled and provider :iiko",
       "Delivest.Integrations.Crm.BranchSettings.active_provider/1; Iiko.configured?/1"},
    "rkeeper" =>
      {"branch: branch_info.crm.rkeeper", "crm.enabled and provider :rkeeper",
       "Delivest.Integrations.Crm.BranchSettings.active_provider/1; Rkeeper.configured?/1"},
    "yandex_delivery" =>
      {"branch: branch_info.yandex_delivery", "branch settings auto_accept/capabilities",
       "Delivest.Integrations.YandexDelivery.Settings.configured?/1"},
    "yandex_eda" =>
      {"network credentials plus branch_info.channels.yandex_eda", "branch settings enabled",
       "Delivest.Integrations.YandexEda.configured?/1; shared Settings.credentials?/1"},
    "yookassa" =>
      {"network: yookassa_settings", "credential completeness",
       "Delivest.Integrations.Yookassa.Settings.complete?/1"},
    "zvonok" =>
      {"network: zvonok_settings", "settings.enabled",
       "Delivest.Integrations.Zvonok.enabled?/0 and configured?/0"}
  }

  @impl Mix.Task
  def run(args) do
    {opts, _, invalid} = OptionParser.parse(args, strict: [write: :boolean, check: :boolean])

    if invalid != [] or opts == [] or (opts[:write] && opts[:check]) do
      Mix.raise("usage: mix admin.inventory --write | --check")
    end

    Mix.Task.run("app.config")
    inventory = build()
    json = Jason.encode_to_iodata!(inventory, pretty: true) |> IO.iodata_to_binary()
    markdown = summary(inventory)

    if opts[:write] do
      File.mkdir_p!(Path.dirname(@snapshot))
      File.write!(@snapshot, json <> "\n")
      File.write!(@summary, markdown)
      Mix.shell().info("Wrote #{@snapshot} and #{@summary}")
    else
      check!(@snapshot, json <> "\n")
      check!(@summary, markdown)
      Mix.shell().info("Admin inventory matches current sources")
    end
  end

  @doc false
  def snapshot, do: build()

  defp check!(path, expected) do
    case File.read(path) do
      {:ok, ^expected} ->
        :ok

      {:ok, _} ->
        Mix.raise(
          "#{path} differs from source inventory; run mix admin.inventory --write and review diff"
        )

      {:error, reason} ->
        Mix.raise("cannot read #{path}: #{inspect(reason)}")
    end
  end

  defp build do
    staff_sources =
      Path.wildcard("#{@staff}/**/*.{ex,heex}")
      |> Enum.reject(
        &(String.contains?(&1, "/foundation/") or
            String.ends_with?(&1, "/foundation_gallery_live.ex"))
      )
      |> Enum.sort()

    domain_sources = Path.wildcard("lib/delivest/**/*.ex") |> Enum.sort()

    schema_sources =
      (domain_sources ++ Path.wildcard("#{@staff}/**/*.ex")) |> Enum.uniq() |> Enum.sort()

    routes = router_screens()
    screens = Enum.reject(routes, &(&1["page_type"] == "service"))
    service_routes = Enum.filter(routes, &(&1["page_type"] == "service"))
    controls = Enum.flat_map(staff_sources, &form_controls/1)
    annotations = Code.eval_file("docs/admin/form-owners.exs") |> elem(0)
    annotated = annotations |> Map.keys() |> Enum.sort()

    actual =
      controls
      |> Enum.map(&String.replace_prefix(&1["form"], @staff <> "/", ""))
      |> Enum.uniq()
      |> Enum.sort()

    if annotated != actual,
      do:
        Mix.raise(
          "form owner annotations differ from live controls: missing #{inspect(actual -- annotated)}, stale #{inspect(annotated -- actual)}"
        )

    Enum.each(annotations, fn {key, {owner, target, canonical}} ->
      if owner in [nil, ""] or target in [nil, ""] or canonical in [nil, ""] or
           not File.exists?(@staff <> "/" <> canonical) or
           (String.starts_with?(owner, "lib/") and not File.exists?(owner)) do
        Mix.raise("invalid form owner annotation for #{key}")
      end
    end)

    schema_entries = schema_fields(schema_sources, controls, annotations)
    fields = form_control_fields(controls, annotations, schema_entries)

    actions = staff_actions(staff_sources)
    features = feature_inventory()
    background_sources = Enum.map(domain_sources, &{&1, File.read!(&1)})

    background =
      background_inventory(background_sources) |> annotate_background(background_sources)

    if Enum.any?(screens, &(&1["page_type"] not in ~w(work_queue list entity settings))) or
         Enum.any?(fields, &(&1["owner"] in [nil, ""] or &1["canonical_form"] in [nil, ""])) or
         Enum.any?(actions, &(&1["id"] in [nil, ""])) do
      Mix.raise("admin inventory has unassigned screen, form control or action")
    end

    %{
      "source_revision" => "source-derived; regenerate after source changes",
      "coverage" => %{
        "router" =>
          "live/get/post/put/patch/delete declarations under /staff; auth login and service routes included",
        "fields" =>
          "Ecto schema field declarations and literal HEEx form controls in staff sources",
        "actions" => "staff handle_event clauses and literal phx-click/phx-submit controls",
        "background" =>
          "optional Background.Registry tasks, Oban cron entries, all Oban.Worker declarations"
      },
      "screens" => screens,
      "service_routes" => service_routes,
      "fields" => fields,
      "schema_census" =>
        Enum.map(schema_entries, &Map.take(&1, ~w(id source field owner type default))),
      "actions" => actions,
      "features_integrations" => features,
      "background" => background
    }
  end

  defp router_screens do
    path = "lib/delivest_web/router.ex"
    {:ok, ast} = Code.string_to_quoted(File.read!(path), columns: true)

    ast
    |> walk_routes([], false, path, [], nil)
    |> Enum.sort_by(& &1["id"])
  end

  defp walk_routes({:__block__, _, nodes}, scopes, staff?, source, hooks, alias_prefix),
    do: Enum.flat_map(nodes, &walk_routes(&1, scopes, staff?, source, hooks, alias_prefix))

  defp walk_routes({:defmodule, _, args}, scopes, staff?, source, hooks, alias_prefix) do
    {body, _} = pop_do(args)
    walk_routes(body, scopes, staff?, source, hooks, alias_prefix)
  end

  defp walk_routes({:scope, _, args}, scopes, staff?, source, hooks, alias_prefix) do
    {body, args} = pop_do(args)

    segment =
      case args do
        [value | _] when is_binary(value) -> value
        _ -> ""
      end

    scope = scopes ++ [segment]
    alias_arg = Enum.at(args, 1)

    prefix =
      if match?({:__aliases__, _, _}, alias_arg) do
        name = Macro.to_string(alias_arg)
        if String.starts_with?(name, "DelivestWeb."), do: name, else: "#{alias_prefix}.#{name}"
      else
        alias_prefix
      end

    walk_routes(body, scope, staff? or segment == "/staff", source, hooks, prefix)
  end

  defp walk_routes({:live_session, _, args}, scopes, staff?, source, hooks, alias_prefix) do
    {body, _} = pop_do(args)
    options = Enum.find(args, &(is_list(&1) and Keyword.has_key?(&1, :on_mount))) || []
    mount = Keyword.get(options, :on_mount, []) |> Enum.map(&Macro.to_string/1)
    walk_routes(body, scopes, staff?, source, hooks ++ mount, alias_prefix)
  end

  defp walk_routes({:if, _, args}, scopes, staff?, source, hooks, alias_prefix) do
    {body, _} = pop_do(args)
    walk_routes(body, scopes, staff?, source, hooks, alias_prefix)
  end

  defp walk_routes({verb, meta, [path | rest]}, scopes, true, source, hooks, alias_prefix)
       when is_atom(verb) and verb in [:get, :post, :put, :patch, :delete, :live] and
              is_binary(path) do
    route = join_path(scopes ++ [path])
    destination = Enum.map_join(rest, ":", &Macro.to_string/1)
    section = section(route)
    type = page_type(route, verb)
    handler_source = handler_source(rest, alias_prefix)
    handler_text = if handler_source, do: File.read!(handler_source), else: ""

    permissions =
      Regex.scan(
        ~r/(?:Permission,\s*|Identity\.(?:can\?|authorize)\([^,]+,\s*)"([a-z_.]+)"/,
        handler_text,
        capture: :all_but_first
      )
      |> List.flatten()
      |> Enum.uniq()
      |> Enum.sort()

    [
      %{
        "id" => "route:#{verb}:#{route}:#{destination}",
        "source" => "#{source}:#{meta[:line]}",
        "route" => "#{String.upcase(to_string(verb))} #{route}",
        "handler" => destination,
        "target_section" => section,
        "page_type" => type,
        "variant" => page_variant(route),
        "data_scope" =>
          if(String.contains?(route, "/b/:branch_slug"),
            do: "branch from URL; server authorization required",
            else:
              if(String.contains?(route, "/branches/:slug"),
                do: "branch object from URL",
                else: "network or all accessible branches; handler decides"
              )
          ),
        "rights" => %{
          "session_hooks" => hooks,
          "handler_permissions" => permissions,
          "handler_source" => handler_source,
          "interpretation" =>
            if(permissions == [],
              do: "no literal Permission/Identity permission in handler",
              else:
                "literal handler permission references; branch authorization may further restrict"
            )
        },
        "feature_dependency" => feature_for(route),
        "branch_switch" => branch_switch(route, type),
        "disposition" => "move to #{section}"
      }
    ]
  end

  defp walk_routes(_, _, _, _, _, _), do: []

  defp handler_source([module | _], alias_prefix) do
    name = "#{alias_prefix}.#{Macro.to_string(module)}"

    Path.wildcard("lib/delivest_web/**/*.ex")
    |> Enum.find(fn path -> String.contains?(File.read!(path), "defmodule #{name} do") end)
  end

  defp handler_source(_, _), do: nil

  defp pop_do(args) do
    {keywords, positional} = List.pop_at(args, -1)

    if is_list(keywords) and Keyword.keyword?(keywords),
      do: {Keyword.get(keywords, :do), positional},
      else: {nil, args}
  end

  defp join_path(segments) do
    "/" <> (segments |> Enum.flat_map(&String.split(&1, "/", trim: true)) |> Enum.join("/"))
  end

  defp section(route) do
    cond do
      String.contains?(route, "/stock_live/") or String.contains?(route, "/stocks") ->
        "Marketing"

      String.contains?(route, "/order_live/") or String.contains?(route, "/pos_live/") or
          String.contains?(route, "/kitchen_live/") ->
        "Orders"

      String.contains?(route, "/product_live/") or String.contains?(route, "/category_live/") or
          String.contains?(route, "/menu_live/") ->
        "Menu"

      String.contains?(route, "/integration_live/") ->
        "Settings / Integrations"

      String.contains?(route, "/branch_live/") ->
        "Settings / Branches"

      String.contains?(route, "/staff_live/") or String.contains?(route, "/role_live/") ->
        "Settings / Team and access"

      String.contains?(route, "/client_live/") or String.contains?(route, "/segment_live/") ->
        "Clients"

      String.contains?(route, "/promotion_live/") or String.contains?(route, "/marketing_live/") or
          String.contains?(route, "/advertising_live/") ->
        "Marketing"

      String.contains?(route, "/finance_live/") or String.contains?(route, "/receipt_live/") ->
        "Finance"

      String.contains?(route, "/delivery_live/") or String.contains?(route, "/courier_live/") ->
        "Delivery"

      String.contains?(route, "/statistics_live/") ->
        "Analytics"

      String.contains?(route, "/franchise_live/") ->
        "Settings / Network and brand"

      String.contains?(route, "/log_live/") or String.contains?(route, "/diagnostics_live/") ->
        "Settings / Data and system"

      String.contains?(route, "/site-snapshot") or String.contains?(route, "/instance-backup") or
        String.contains?(route, "/diagnostics") or String.contains?(route, "/logs") ->
        "Settings / Data and system"

      String.contains?(route, "/marketing/bonuses") or String.contains?(route, "/loyalty") ->
        "Settings / Loyalty"

      String.contains?(route, "/integrations") ->
        "Settings / Integrations"

      String.contains?(route, "/delivery/address") or String.contains?(route, "/delivery/zones") ->
        "Settings / Delivery"

      String.contains?(route, "/franchise") ->
        "Settings / Network and brand"

      String.contains?(route, "/branches") ->
        "Settings / Branches"

      String.contains?(route, "/employee") or String.contains?(route, "/roles") ->
        "Settings / Team and access"

      String.contains?(route, "/finance") ->
        "Finance"

      String.contains?(route, "/delivery") or String.contains?(route, "/deliveries") or
          String.contains?(route, "/couriers") ->
        "Delivery"

      String.contains?(route, "/orders") or String.contains?(route, "/kitchen") or
          String.contains?(route, "/pos") ->
        "Orders"

      String.contains?(route, "/products") or String.contains?(route, "/categories") or
          String.contains?(route, "/menu") ->
        "Menu"

      String.contains?(route, "/clients") or String.contains?(route, "/segments") ->
        "Clients"

      String.contains?(route, "/marketing") or String.contains?(route, "/promotions") or
          String.contains?(route, "/advertising") ->
        "Marketing"

      String.contains?(route, "/statistics") ->
        "Analytics"

      String.contains?(route, "/settings") ->
        "Settings"

      String.contains?(route, "/dashboard") ->
        "Overview"

      true ->
        "System / staff service"
    end
  end

  defp page_type(route, verb) do
    cond do
      verb != :live or route in ["/staff/auth/login", "/staff/foundation-gallery"] ->
        "service"

      String.ends_with?(route, "/delivery") or route == "/staff/branches/new" or
        String.ends_with?(route, "/finance/payments") or
          String.ends_with?(route, "/delivery/couriers") ->
        "settings"

      String.contains?(route, "/integrations") or String.contains?(route, "/settings") or
        String.contains?(route, "/loyalty") or String.contains?(route, "/franchise") or
        String.contains?(route, "/marketing/bonuses") or
        String.contains?(route, "/delivery/zones") or String.contains?(route, "/delivery/address") or
          Regex.match?(~r{/branches/[^/]+/edit}, route) ->
        "settings"

      String.contains?(route, "/kitchen") or String.contains?(route, "/pos") or
        Regex.match?(~r{/orders$}, route) or String.contains?(route, "/deliveries") or
          Regex.match?(~r{/couriers$}, route) ->
        "work_queue"

      String.contains?(route, "/:id") or String.ends_with?(route, "/new") or
          String.ends_with?(route, "/edit") ->
        "entity"

      true ->
        "list"
    end
  end

  defp page_variant(route) do
    cond do
      String.ends_with?(route, "/delivery") -> "hub"
      route == "/staff/branches/new" -> "branch creation"
      String.contains?(route, "/kitchen") -> "fullscreen kitchen"
      String.contains?(route, "/pos") -> "fullscreen POS"
      String.contains?(route, "/dashboard") -> "overview"
      String.contains?(route, "/statistics") -> "analytics"
      true -> nil
    end
  end

  defp branch_switch(route, type) do
    cond do
      String.contains?(route, "/branches/:slug/edit") ->
        "open same branch settings subsection for selected branch; reauthorize object"

      String.contains?(route, "/b/:branch_slug") and type == "entity" ->
        "go to same section list in new branch; discard object ID"

      String.contains?(route, "/b/:branch_slug") and type == "settings" ->
        "open same subsection for new branch if available"

      String.contains?(route, "/b/:branch_slug") ->
        "open same list/queue for new branch; reset selection and page"

      type == "settings" ->
        "network setting stays network-scoped; branch selection is explicit navigation"

      true ->
        "network/all-branches scope stays explicit; no implicit branch filtering"
    end
  end

  defp feature_for(route) do
    cond do
      String.contains?(route, "/segments") -> "segments"
      String.contains?(route, "/marketing/policies") -> "marketing_policies"
      true -> "no registry key established at route declaration"
    end
  end

  defp form_controls(path) do
    source = File.read!(path)
    # HEEx is not Elixir AST. Include nested inputs_for bindings, notably CRM
    # provider settings, as well as literal @form references used by components.
    direct =
      Regex.scan(~r/(@\w+|\w+_form)\[:([a-zA-Z_][a-zA-Z_0-9]*)\]/, source, return: :index)
      |> Enum.map(fn [{offset, _}, {bind_at, bind_size}, {field_offset, length}] ->
        %{
          "field" => binary_part(source, field_offset, length),
          "binding" => binary_part(source, bind_at, bind_size),
          "form" => path,
          "source" => "#{path}:#{line_at(source, offset)}"
        }
      end)

    nested =
      Regex.scan(~r/field=\{([a-z]\w*)\[:([a-zA-Z_][a-zA-Z_0-9]*)\]\}/, source, return: :index)
      |> Enum.map(fn [{offset, _}, {bind_at, bind_size}, {field_at, field_size}] ->
        %{
          "field" => binary_part(source, field_at, field_size),
          "binding" => binary_part(source, bind_at, bind_size),
          "form" => path,
          "source" => "#{path}:#{line_at(source, offset)}"
        }
      end)

    names =
      Regex.scan(~r/<(?:input|select|textarea|\.input|\.select|\.textarea)\b[^>]*>/s, source,
        return: :index
      )
      |> Enum.flat_map(fn [{offset, size}] ->
        tag = binary_part(source, offset, size)
        literal = Regex.run(~r/\bname=["']([^"']+)["']/, tag)

        dynamic =
          case Regex.run(~r/\bname=\{/, tag, return: :index) do
            [{relative, _}] ->
              read_braced_expression(source, offset + relative + byte_size("name={"))

            _ ->
              nil
          end

        required = Regex.match?(~r/(?:^|\s)required(?:\s|=|>)/, tag)

        default =
          case Regex.run(~r/\bvalue=["']([^"']*)["']/, tag) do
            [_, value] when value in ["", "true", "false", "0", "1"] -> value
            _ -> nil
          end

        cond do
          literal && Enum.at(literal, 1) not in ["_csrf_token", "_method"] ->
            name = Enum.at(literal, 1)

            [
              %{
                "field" => name,
                "binding" => "name:#{name}",
                "form" => path,
                "source" => "#{path}:#{line_at(source, offset)}",
                "expression" => nil,
                "html_required" => required,
                "html_default" => default
              }
            ]

          dynamic ->
            expression = String.trim(dynamic)

            [
              %{
                "field" => "name-expression:#{expression}",
                "binding" => "dynamic-name",
                "form" => path,
                "source" => "#{path}:#{line_at(source, offset)}",
                "expression" => expression,
                "html_required" => required,
                "html_default" => default
              }
            ]

          true ->
            []
        end
      end)

    # The shared FilterBar renders its input in a component. Record each
    # production caller's concrete query name at the call site so migrations
    # cannot silently remove a search control from the source census.
    filter_bar_search =
      Regex.scan(~r/<\.filter_bar\b[^>]*>/s, source, return: :index)
      |> Enum.flat_map(fn [{offset, size}] ->
        tag = binary_part(source, offset, size)

        with [_, id] <- Regex.run(~r/\bid="([^"]+)"/, tag),
             [_, query_name] <- Regex.run(~r/\bquery_name="([^"]+)"/, tag) do
          [
            %{
              "field" => query_name,
              "binding" => "filter_bar:#{id}",
              "form" => path,
              "source" => "#{path}:#{line_at(source, offset)}",
              "expression" => nil,
              "html_required" => false,
              "html_default" => nil
            }
          ]
        else
          _ -> []
        end
      end)

    dynamic_fields =
      Regex.scan(~r/\bfield=\{([^}]+)\}/, source, return: :index)
      |> Enum.flat_map(fn [{offset, _}, {expr_at, expr_size}] ->
        expression = binary_part(source, expr_at, expr_size) |> String.trim()

        if Regex.match?(~r/^(?:@\w+|[a-z]\w*)\[:[a-zA-Z_]\w*\]$/, expression),
          do: [],
          else: [
            %{
              "field" => "field-expression:#{expression}",
              "binding" => "dynamic-field",
              "form" => path,
              "source" => "#{path}:#{line_at(source, offset)}",
              "expression" => expression
            }
          ]
      end)

    (direct ++ nested ++ names ++ filter_bar_search ++ dynamic_fields)
    |> Enum.uniq_by(&{&1["field"], &1["form"], &1["binding"]})
  end

  defp read_braced_expression(source, start) do
    tail = binary_part(source, start, byte_size(source) - start)

    result =
      tail
      |> :binary.bin_to_list()
      |> Enum.with_index()
      |> Enum.reduce_while(1, fn
        {?{, _}, depth -> {:cont, depth + 1}
        {?}, index}, 1 -> {:halt, {:found, index}}
        {?}, _}, depth -> {:cont, depth - 1}
        _, depth -> {:cont, depth}
      end)

    case result do
      {:found, count} -> binary_part(tail, 0, count)
      _ -> nil
    end
  end

  defp schema_fields(paths, controls, annotations) do
    Enum.flat_map(paths, fn path ->
      source = File.read!(path)

      if String.contains?(source, "use Ecto.Schema") or
           String.contains?(source, "embedded_schema") do
        case Code.string_to_quoted(source, columns: true) do
          {:ok, ast} ->
            required = required_fields(ast)
            validators = field_validators(ast)

            {_ast, fields} =
              Macro.prewalk(ast, [], fn
                {:field, meta, [name, type | options]} = node, acc when is_atom(name) ->
                  default =
                    case options do
                      [opts | _] when is_list(opts) ->
                        if Keyword.has_key?(opts, :default),
                          do: Macro.to_string(Keyword.fetch!(opts, :default)),
                          else: "not declared"

                      _ ->
                        "not declared"
                    end

                  {node, [{name, type, default, meta[:line]} | acc]}

                node, acc ->
                  {node, acc}
              end)

            Enum.map(fields, fn {name, type, default, line} ->
              field = to_string(name)
              forms = linked_forms(path, field, controls, annotations)

              targets =
                Enum.map(forms, fn form ->
                  key = String.replace_prefix(form, @staff <> "/", "")
                  {_, section, canonical} = Map.fetch!(annotations, key)
                  {section, @staff <> "/" <> canonical}
                end)
                |> Enum.uniq()

              target = if length(targets) == 1, do: hd(targets), else: nil

              %{
                "id" => "schema:#{path}:#{field}",
                "source" => "#{path}:#{line}",
                "field" => field,
                "owner" => path,
                "type" => Macro.to_string(type),
                "validation" => Map.get(validators, field, []),
                "required" =>
                  if(field in required,
                    do: "declared validate_required call; may be conditional",
                    else: "no literal validate_required call for field"
                  ),
                "default" => default,
                "current_forms" => forms,
                "canonical_form" => if(target, do: elem(target, 1), else: nil),
                "target_section" =>
                  if(target, do: elem(target, 0), else: "Domain only / no staff editor"),
                "disposition" =>
                  if(forms == [],
                    do: "retain domain field; no literal staff control found",
                    else:
                      if(target,
                        do: "move to #{elem(target, 0)}",
                        else: "multiple target annotations; reconcile editors"
                      )
                  )
              }
            end)

          {:error, _} ->
            []
        end
      else
        []
      end
    end)
    |> Enum.sort_by(& &1["id"])
  end

  defp linked_forms(owner, field, controls, annotations) do
    Enum.filter(controls, fn control ->
      key = String.replace_prefix(control["form"], @staff <> "/", "")
      {annotated_owner, _, _} = Map.fetch!(annotations, key)
      control["field"] == field and control_owner(annotated_owner, key, control) == owner
    end)
    |> Enum.map(& &1["form"])
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp control_owner(owner, key, control) do
    binding = control["binding"]
    field = control["field"]

    cond do
      String.starts_with?(binding, "filter_bar:") ->
        "transient search/query operation in #{key}"

      field in ~w(q query location_query) ->
        "transient search/query operation in #{key}"

      key in ["branch_live/branch_form_component.ex", "branch_live/location_fields.ex"] and
          binding in ~w(method kitchen) ->
        if(binding == "method",
          do: "lib/delivest/identity/branch/fulfillment_settings.ex",
          else: "lib/delivest/identity/branch/kitchen_settings.ex"
        )

      key in ["branch_live/branch_form_component.ex", "branch_live/location_fields.ex"] and
          field in ~w(name slug code is_active) ->
        "lib/delivest/identity/branch.ex"

      key in ["branch_live/branch_form_component.ex", "branch_live/location_fields.ex"] and
          field in ~w(address city latitude longitude phone_number delivery_time manual_rating timezone working_hours vk_url whatsapp_url instagram_url) ->
        "lib/delivest/identity/branch/branch_info.ex"

      key == "integration_live/frontpad.ex" and
          (binding in ~w(frontpad codes) or
             String.starts_with?(control["field"], "field-expression:codes[")) ->
        "lib/delivest/integrations/frontpad/settings.ex"

      key == "integration_live/iiko.ex" and binding in ~w(iiko codes) ->
        "lib/delivest/integrations/iiko/settings.ex"

      key == "integration_live/rkeeper.ex" and binding in ~w(rkeeper codes) ->
        "lib/delivest/integrations/rkeeper/settings.ex"

      key == "integration_live/fiscal.ex" and binding == "atol" ->
        "lib/delivest/integrations/atol_online/settings.ex"

      key == "delivery_live/zones.ex" and
          control["field"] in ~w(color delivery_minutes enabled name radius_km) ->
        "lib/delivest/delivery/zone.ex"

      key == "promotion_live/promotion_form_component.ex" and
          String.contains?(control["field"], "builder[") ->
        "lib/delivest/promo/dsl.ex"

      true ->
        owner
    end
  end

  defp required_fields(ast) do
    attributes = literal_field_attributes(ast)

    {_, names} =
      Macro.prewalk(ast, [], fn
        {:validate_required, _, [fields | _]} = node, acc when is_list(fields) ->
          {node, Enum.filter(fields, &is_atom/1) ++ acc}

        {:validate_required, _, [{:@, _, [{name, _, _}]} | _]} = node, acc ->
          {node, Map.get(attributes, name, []) ++ acc}

        node, acc ->
          {node, acc}
      end)

    Enum.map(names, &to_string/1)
  end

  defp literal_field_attributes(ast) do
    {_, attrs} =
      Macro.prewalk(ast, %{}, fn
        {:@, _, [{name, _, [values]}]} = node, acc when is_list(values) ->
          {node, Map.put(acc, name, Enum.filter(values, &is_atom/1))}

        node, acc ->
          {node, acc}
      end)

    attrs
  end

  defp field_validators(ast) do
    attrs = literal_field_attributes(ast)

    {_, validators} =
      Macro.prewalk(ast, %{}, fn
        {name, _, [fields | _]} = node, acc when is_atom(name) ->
          if String.starts_with?(Atom.to_string(name), "validate_") or
               name in [:unique_constraint, :foreign_key_constraint] do
            names =
              case fields do
                atom when is_atom(atom) -> [atom]
                list when is_list(list) -> Enum.filter(list, &is_atom/1)
                {:@, _, [{attr, _, _}]} -> Map.get(attrs, attr, [])
                _ -> []
              end

            updated =
              Enum.reduce(names, acc, fn field, result ->
                Map.update(result, to_string(field), [to_string(name)], &[to_string(name) | &1])
              end)

            {node, updated}
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    Map.new(validators, fn {field, names} -> {field, Enum.uniq(names) |> Enum.sort()} end)
  end

  defp form_control_fields(controls, annotations, schema_entries) do
    schema_by_id = Map.new(schema_entries, &{&1["id"], &1})

    controls
    |> Enum.map(fn control ->
      key = String.replace_prefix(control["form"], @staff <> "/", "")
      {annotated_owner, target, canonical} = Map.fetch!(annotations, key)
      owner = control_owner(annotated_owner, key, control)

      resolved_field =
        case Regex.run(~r/@form\[:([a-zA-Z_]\w*)\]\.name/, control["expression"] || "") do
          [_, field] -> field
          _ -> control["field"]
        end

      schema = Map.get(schema_by_id, "schema:#{owner}:#{resolved_field}")

      form_schema =
        Map.get(
          schema_by_id,
          "schema:lib/delivest_web/live/staff/branch_live/branch_form.ex:#{resolved_field}"
        )

      branch_control? =
        key in ["branch_live/branch_form_component.ex", "branch_live/location_fields.ex"]

      validation =
        if (branch_control? and form_schema) && schema,
          do: Enum.uniq(form_schema["validation"] ++ schema["validation"]) |> Enum.sort(),
          else:
            if(schema, do: schema["validation"], else: "form operation; no direct schema field")

      canonical_path = @staff <> "/" <> canonical

      %{
        "id" => "form:#{control["form"]}:#{control["binding"]}:#{control["field"]}",
        "source" => control["source"],
        "field" => control["field"],
        "binding" => control["binding"],
        "resolved_field" => resolved_field,
        "expression" => control["expression"],
        "name_template" => name_template(control["expression"]),
        "owner" => owner,
        "schema_field" => if(schema, do: schema["id"], else: nil),
        "type" => "literal staff form control",
        "validation" => validation,
        "required" =>
          if(schema,
            do: schema["required"],
            else:
              if(String.starts_with?(owner, "transient search/query operation"),
                do: "not applicable: transient search/query input",
                else:
                  if(control["html_required"],
                    do: "HTML required attribute; server validation must be checked",
                    else: "not declared in control/owner schema"
                  )
              )
          ),
        "default" =>
          if(schema,
            do: schema["default"],
            else:
              if(String.starts_with?(owner, "transient search/query operation"),
                do: "not applicable: transient query value",
                else: control["html_default"] || "not declared in control/owner schema"
              )
          ),
        "current_forms" => [control["form"]],
        "canonical_form" => canonical_path,
        "target_section" => target,
        "disposition" =>
          if(canonical_path == control["form"],
            do: "retain canonical editor in #{target}",
            else: "merge into #{canonical_path} in #{target}"
          )
      }
    end)
    |> Enum.sort_by(& &1["id"])
  end

  defp name_template(nil), do: nil

  defp name_template(expression) do
    if String.starts_with?(expression, "\""),
      do: expression |> String.trim("\"") |> String.replace(~r/#\{[^}]+\}/, "<dynamic>"),
      else: nil
  end

  defp staff_actions(paths) do
    events =
      Enum.flat_map(paths ++ Path.wildcard("lib/delivest_web/hooks/*.ex"), fn path ->
        source = File.read!(path)

        if String.ends_with?(path, ".ex") do
          case Code.string_to_quoted(source, columns: true) do
            {:ok, ast} ->
              {_ast, clauses} =
                Macro.prewalk(ast, [], fn
                  {kind, meta, [{:handle_event, _, [event | _]} | body]} = node, acc
                  when kind in [:def, :defp] and is_binary(event) ->
                    {node, [{event, meta[:line], body, node} | acc]}

                  {kind, meta, [{:when, _, [{:handle_event, _, [event | _]} | _]} | body]} = node,
                  acc
                  when kind in [:def, :defp] and is_binary(event) ->
                    {node, [{event, meta[:line], body, node} | acc]}

                  {kind, meta, [{:when, _, [{:handle_event, _, [_variable | _]}, guard]} | body]} =
                      node,
                  acc
                  when kind in [:def, :defp] ->
                    names =
                      case Regex.run(~r/~w\(([^)]+)\)/, Macro.to_string(guard)) do
                        [_, words] -> String.split(words, ~r/\s+/, trim: true)
                        _ -> []
                      end

                    {node, Enum.map(names, &{&1, meta[:line], body, node}) ++ acc}

                  node, acc ->
                    {node, acc}
                end)

              clauses
              |> Enum.reverse()
              |> Enum.map(fn {event, line, body, node} ->
                action(path, event, line, body, node, source)
              end)
              |> assign_duplicate_ordinals()

            {:error, _} ->
              []
          end
        else
          []
        end
      end)

    controls =
      Enum.flat_map(paths, fn path ->
        source = File.read!(path)

        Regex.scan(~r/<([\w.:-]+)\b[^>]*\bphx-(click|submit)=["']([^"']+)["'][^>]*>/s, source,
          return: :index
        )
        |> Enum.map(fn [{offset, size}, _, _, {event_at, event_size}] ->
          event = binary_part(source, event_at, event_size)
          opening = binary_part(source, offset, size)
          label = control_label(source, offset, size, opening)

          %{
            "id" => stable_control_identity(path, event, opening, label),
            "source" => "#{path}:#{line_at(source, offset)}",
            "event" => event,
            "label" => label,
            "rights" => %{
              "inline" => literal_permissions(opening),
              "module_references" => literal_permissions(source)
            },
            "availability" =>
              if(String.contains?(opening, ":if="),
                do: "conditional :if in source",
                else: "no inline :if"
              ),
            "confirmation" =>
              if(String.contains?(opening, "confirm"),
                do: "confirmation marker in control",
                else: "no inline confirmation marker"
              ),
            "operation" => "phx event #{event}",
            "result" => [],
            "error_state" => [],
            "target_section" => section(path),
            "disposition" => "retain control in #{section(path)}"
          }
        end)
        |> assign_duplicate_ordinals()
      end)

    controls =
      Enum.map(controls, fn control ->
        path = control["source"] |> String.split(":") |> hd()
        event = control["event"]

        exact =
          Enum.filter(
            events,
            &(&1["event"] == event and String.starts_with?(&1["source"], path <> ":"))
          )

        family =
          if Path.basename(Path.dirname(path)) == "components",
            do: Path.dirname(Path.dirname(path)),
            else: Path.dirname(path)

        family_candidates =
          if exact == [],
            do:
              Enum.filter(events, fn entry ->
                event_path = entry["source"] |> String.split(":") |> hd()
                entry["event"] == event and String.starts_with?(event_path, family <> "/")
              end),
            else: exact

        candidates =
          if family_candidates == [] do
            Enum.filter(events, fn entry ->
              entry["event"] == event and
                String.starts_with?(entry["source"], "lib/delivest_web/hooks/")
            end)
          else
            family_candidates
          end

        control
        |> Map.put("handler_clauses", Enum.map(candidates, & &1["id"]))
        |> Map.put("operation", Enum.flat_map(candidates, & &1["operation"]) |> Enum.uniq())
        |> Map.put("result", Enum.flat_map(candidates, & &1["result"]) |> Enum.uniq())
        |> Map.put("error_state", Enum.map(candidates, & &1["error_state"]) |> Enum.uniq())
        |> Map.put(
          "disposition",
          if(candidates == [],
            do: "delete during migration; receiver absent in lib/delivest_web and assets/js",
            else: control["disposition"]
          )
        )
      end)

    Enum.sort_by(events ++ controls, & &1["id"])
  end

  defp control_label(source, offset, size, opening) do
    tail = binary_part(source, offset + size, byte_size(source) - offset - size)

    candidate =
      if String.starts_with?(opening, "<.form") or String.starts_with?(opening, "<form") do
        form_body =
          tail
          |> String.split("</.form>", parts: 2)
          |> hd()
          |> String.split("</form>", parts: 2)
          |> hd()

        case Regex.run(~r/<button[^>]*type=["']submit["'][^>]*>(.*?)<\/button>/s, form_body) do
          [_, body] -> body
          _ -> ""
        end
      else
        tail |> String.split("</", parts: 2) |> hd()
      end

    case Regex.run(~r/gettext\("([^"]+)"\)/, candidate) do
      [_, label] ->
        label

      _ ->
        clean =
          candidate
          |> String.replace(~r/<[^>]+>/, "")
          |> String.replace(~r/\s+/, " ")
          |> String.trim()

        if clean == "" do
          case Regex.run(~r/(?:aria-label|title)=["']([^"']+)["']/, opening) do
            [_, label] -> label
            _ -> "unlabelled/icon control at source anchor"
          end
        else
          String.slice(clean, 0, 120)
        end
    end
  end

  defp action(path, event, line, body, node, source) do
    text = Macro.to_string(body)

    calls =
      Regex.scan(~r/\b([A-Z][\w.]*\.[a-z][\w!?]*)\s*\(/, text, capture: :all_but_first)
      |> List.flatten()
      |> Enum.uniq()
      |> Enum.sort()

    labels =
      Regex.scan(
        ~r/<[^>]+phx-(?:click|submit)=["']#{Regex.escape(event)}["'][^>]*>\s*([^<]{1,120})/s,
        source,
        capture: :all_but_first
      )
      |> List.flatten()
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    %{
      "id" => stable_action_identity(path, event, node),
      "source" => "#{path}:#{line}",
      "event" => event,
      "label" => if(labels == [], do: "event: #{event}", else: Enum.join(labels, " / ")),
      "rights" => %{
        "clause" => literal_permissions(text),
        "module_references" => literal_permissions(source)
      },
      "availability" =>
        if(Regex.match?(~r/\b(if|with|cond|case)\b/, text),
          do: "conditional branch in handler clause",
          else: "no inline conditional in handler clause"
        ),
      "confirmation" =>
        if(String.contains?(source, "confirm_dialog") or String.contains?(source, "confirmation"),
          do: "confirmation marker in module; inspect event flow",
          else: "no confirmation marker found in module"
        ),
      "operation" => calls,
      "result" =>
        Enum.filter(~w(put_flash push_patch push_navigate redirect), &String.contains?(text, &1)),
      "error_state" =>
        if(String.contains?(text, ":error"),
          do: "explicit :error branch/reference",
          else: "no explicit :error in clause"
        ),
      "target_section" => section(path),
      "disposition" => "retain operation; move control with #{section(path)}"
    }
  end

  @doc false
  def stable_action_identity(path, event, ast) do
    "event:#{path}:#{event}:#{ast_digest(ast)}"
  end

  @doc false
  def stable_control_identity(path, event, opening, label) do
    explicit_id =
      case Regex.run(~r/\bid=["']([^"']+)["']/, opening) do
        [_, id] -> "dom:#{id}"
        _ -> "signature:#{digest(String.replace(opening, ~r/\s+/, " ") <> label)}"
      end

    "control:#{path}:#{event}:#{explicit_id}"
  end

  defp assign_duplicate_ordinals(entries) do
    {result, _} =
      Enum.map_reduce(entries, %{}, fn entry, counts ->
        id = entry["id"]
        ordinal = Map.get(counts, id, 0) + 1
        updated = Map.put(entry, "id", "#{id}:#{ordinal}")
        {updated, Map.put(counts, id, ordinal)}
      end)

    result
  end

  defp ast_digest(ast) do
    ast
    |> Macro.prewalk(fn
      {name, _meta, args} when is_atom(name) and is_list(args) -> {name, [], args}
      node -> node
    end)
    |> Macro.to_string()
    |> digest()
  end

  defp digest(value) do
    :crypto.hash(:sha256, value)
    |> Base.encode16(case: :lower)
    |> binary_part(0, 16)
  end

  defp literal_permissions(source) do
    Regex.scan(
      ~r/(?:Permission,\s*|Identity\.(?:can\?|authorize)\([^,]+,\s*)"([a-z_.]+)"/,
      source,
      capture: :all_but_first
    )
    |> List.flatten()
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp feature_inventory do
    feature_path = "lib/delivest/features/registry.ex"
    {:ok, ast} = Code.string_to_quoted(File.read!(feature_path))

    {_, attrs} =
      Macro.prewalk(ast, [], fn
        {:@, _, [{name, _, [value]}]} = node, acc when name in [:features, :dependencies] ->
          {node, [{name, value} | acc]}

        node, acc ->
          {node, acc}
      end)

    names = attrs |> Keyword.fetch!(:features)
    dependencies = attrs |> Keyword.fetch!(:dependencies) |> Code.eval_quoted() |> elem(0)

    features =
      Enum.map(names, fn name ->
        %{
          "id" => "feature:#{name}",
          "source" => feature_path,
          "scope" => "franchise gate, optional branch gate",
          "stored_configuration" => "feature_gates.enabled/generation (Delivest.Features.Gate)",
          "desired_enabled" => "gate.enabled at requested scope",
          "effective_enabled" =>
            "Delivest.Features.enabled?/2 checks parent, branch and dependency closure",
          "dependencies" => Map.get(dependencies, name, []),
          "execution_owner" => "Delivest.Features / Delivest.Background.Registry",
          "disposition" => "retain; show in Settings / Features and connections"
        }
      end)

    integrations =
      Path.wildcard("lib/delivest/integrations/*/settings.ex")
      |> Enum.sort()
      |> Enum.map(fn path ->
        provider = path |> Path.dirname() |> Path.basename()
        {scope, desired, effective} = Map.fetch!(@integration_semantics, provider)
        source = File.read!(path)

        fields =
          Regex.scan(~r/\bfield\s+:([a-zA-Z_][a-zA-Z_0-9]*)\s*,/, source, capture: :all_but_first)
          |> List.flatten()
          |> Enum.uniq()
          |> Enum.sort()

        %{
          "id" => "integration:#{provider}",
          "source" => path,
          "scope" => scope,
          "stored_configuration" => fields,
          "desired_enabled" => desired,
          "effective_enabled" => effective,
          "dependencies" => [],
          "execution_owner" => Path.dirname(path),
          "disposition" => "retain; consolidate credentials in Settings / Integrations"
        }
      end)

    supplemental =
      [
        {"ycart", "lib/delivest/identity/branch/ycart_settings.ex", "branch_info.ycart",
         "settings.enabled", "Delivest.Identity.Branch.YcartSettings changeset and caller"},
        {"fiscal", "lib/delivest/fiscal/branch_settings.ex", "branch_info.fiscal",
         "settings.mode", "Delivest.Fiscal.BranchSettings.own?/1 and Fiscal callers"},
        {"routes", "lib/delivest/integrations/channels/branch_settings.ex",
         "branch_info.channels and crm.sources", "per-channel enabled and source routing",
         "Delivest.Integrations.Channels and Crm.BranchSettings.provider_for/2"}
      ]
      |> Enum.map(fn {name, path, scope, desired, effective} ->
        %{
          "id" => "integration:#{name}",
          "source" => path,
          "scope" => scope,
          "stored_configuration" =>
            Regex.scan(~r/\bfield\s+:([a-zA-Z_][a-zA-Z_0-9]*)\s*,/, File.read!(path),
              capture: :all_but_first
            )
            |> List.flatten()
            |> Enum.uniq()
            |> Enum.sort(),
          "desired_enabled" => desired,
          "effective_enabled" => effective,
          "dependencies" => [],
          "execution_owner" => Path.dirname(path),
          "disposition" => "retain; consolidate in Settings / Integrations"
        }
      end)

    Enum.sort_by(features ++ integrations ++ supplemental, & &1["id"])
  end

  defp background_inventory(sources) do
    registry = "lib/delivest/background/registry.ex"
    {:ok, ast} = Code.string_to_quoted(File.read!(registry))

    {_, attrs} =
      Macro.prewalk(ast, [], fn
        {:@, _, [{:tasks, _, [value]}]} = node, acc -> {node, [value | acc]}
        node, acc -> {node, acc}
      end)

    tasks_ast = hd(attrs)
    {:%{}, _, entries} = tasks_ast

    optional =
      Enum.map(entries, fn {kind, {:%{}, _, props}} ->
        feature = Keyword.fetch!(props, :feature)
        handler = Macro.to_string(Keyword.fetch!(props, :handler))
        {handler_source, handler_text} = module_source(handler, sources) || {nil, ""}

        %{
          "id" => "optional:#{kind}",
          "source" => registry,
          "producer_scheduler" =>
            "Delivest.Background.Dispatcher (5-minute Oban cron); manual request if Registry.manual?",
          "worker_process" => "Delivest.Background.Runner -> #{handler}",
          "frequency" => Macro.to_string(Keyword.fetch!(props, :interval)),
          "external_call" => direct_external_call(handler_text),
          "enable_gate" =>
            "Delivest.Background.checkpoint + Delivest.Features snapshot for #{feature}",
          "on_disable" =>
            if(String.contains?(handler_text, "def on_disable("),
              do: "#{handler_source}:on_disable/1",
              else: "no on_disable/1 in handler; Registry skips callback"
            ),
          "in_flight_obligation" =>
            "Runner checkpoints before execution; publication fencing and external side effects require handler-specific review",
          "disposition" => "retain; audit disable semantics before migration"
        }
      end)

    cron_source = "config/config.exs"
    cron_text = File.read!(cron_source)

    cron =
      Regex.scan(
        ~r/\{"([^\"]+)",\s*(Delivest\.[\w.]+)(?:,\s*args:\s*%\{poller:\s*"([^"]+)"\})?\}/,
        cron_text
      )
      |> Enum.map(fn [raw, schedule, worker | rest] ->
        suffix = List.first(rest) || ""
        {_worker_source, worker_text} = module_source(worker, sources) || {nil, ""}

        %{
          "id" => "cron:#{worker}:#{suffix}:#{schedule}",
          "source" =>
            "#{cron_source}:#{line_at(cron_text, :binary.match(cron_text, raw) |> elem(0))}",
          "producer_scheduler" => "Oban cron at #{cron_source}",
          "worker_process" => worker,
          "frequency" => schedule,
          "external_call" => direct_external_call(worker_text),
          "enable_gate" => direct_gate(worker_text),
          "on_disable" => "no disable contract at cron declaration",
          "in_flight_obligation" => "inspect retries, external idempotency and pending jobs",
          "disposition" => "retain; review job-specific gate"
        }
      end)

    workers =
      Enum.flat_map(sources, fn {path, source} ->
        if String.contains?(source, "use Oban.Worker") do
          case Regex.run(~r/defmodule\s+(Delivest\.[\w.]+)/, source) do
            [_, module] ->
              maintenance = maintenance_task(module, sources)

              cron_schedules =
                Enum.filter(cron, &(&1["worker_process"] == module))
                |> Enum.map(& &1["frequency"])

              producers =
                producer_refs(module, path, sources) ++
                  if(maintenance,
                    do: [
                      "lib/delivest/maintenance/registry.ex:#{maintenance.line} via DispatchWorker"
                    ],
                    else: []
                  ) ++ if(cron_schedules == [], do: [], else: ["config/config.exs Oban cron"])

              [
                %{
                  "id" => "worker:#{module}",
                  "source" => path,
                  "producer_scheduler" => Enum.uniq(producers) |> Enum.sort(),
                  "worker_process" => module,
                  "frequency" =>
                    if(maintenance,
                      do: "daily at local hour #{maintenance.hour}",
                      else:
                        if(cron_schedules == [],
                          do: "event-driven",
                          else: Enum.join(cron_schedules, ", ")
                        )
                    ),
                  "external_call" => direct_external_call(source),
                  "enable_gate" => direct_gate(source),
                  "on_disable" => "not established by worker declaration",
                  "in_flight_obligation" =>
                    "Oban retry/pending job obligations remain; inspect worker-specific external side effects",
                  "disposition" => "retain; review job-specific gate"
                }
              ]

            _ ->
              []
          end
        else
          []
        end
      end)

    Enum.sort_by(optional ++ cron ++ workers, & &1["id"])
  end

  defp module_source(module, sources) do
    Enum.find(sources, fn {_path, source} ->
      String.contains?(source, "defmodule #{module} do")
    end)
  end

  defp maintenance_task(module, sources) do
    path = "lib/delivest/maintenance/registry.ex"
    source = sources |> List.keyfind(path, 0) |> elem(1)

    case Regex.run(
           ~r/%\{\s*key:\s*"[^"]+",\s*worker:\s*#{Regex.escape(module)},\s*scope:\s*:\w+,\s*hour:\s*(\d+)/s,
           source,
           return: :index
         ) do
      [{offset, _}, {hour_at, hour_len}] ->
        %{line: line_at(source, offset), hour: binary_part(source, hour_at, hour_len)}

      _ ->
        nil
    end
  end

  defp producer_refs(module, own_path, sources) do
    parts = String.split(module, ".")
    short = List.last(parts)
    prefix = parts |> Enum.drop(-1) |> Enum.join(".")

    sources
    |> Enum.reject(fn {path, _source} -> path == own_path end)
    |> Enum.flat_map(fn {path, source} ->
      alias_present =
        String.contains?(source, "alias #{module}") or
          Regex.match?(
            ~r/alias\s+#{Regex.escape(prefix)}\.\{[^}]*\b#{Regex.escape(short)}\b/s,
            source
          )

      source
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Enum.filter(fn {line, _} ->
        Enum.any?(~w(new enqueue schedule), fn fun ->
          String.contains?(line, "#{module}.#{fun}(") or
            (alias_present and String.contains?(line, "#{short}.#{fun}("))
        end)
      end)
      |> Enum.map(fn {_, line} -> "#{path}:#{line}" end)
    end)
    |> Enum.sort()
  end

  defp direct_gate(source) do
    cond do
      String.contains?(source, "Features.snapshot(") or
          String.contains?(source, "Features.enabled?(") ->
        "direct Features gate reference in worker"

      String.contains?(source, "Background.checkpoint(") ->
        "direct Background.checkpoint in worker"

      String.contains?(source, "configured?(") or String.contains?(source, "enabled?(") ->
        "direct provider/config enabled check; inspect conditions"

      true ->
        "absent in worker source; a caller or callee may still gate"
    end
  end

  defp direct_external_call(source) do
    cond do
      String.contains?(source, "Req.") ->
        "direct Req call in worker/handler"

      String.contains?(source, "HTTP") or String.contains?(source, "Client.") or
          String.contains?(source, "Api.") ->
        "direct HTTP/client reference; inspect callee"

      true ->
        "no direct HTTP client reference; transitive external calls not assessed"
    end
  end

  defp annotate_background(entries, sources) do
    semantics = Code.eval_file("docs/admin/background-semantics.exs") |> elem(0)

    pollers =
      Enum.map(@poller_keys, fn {key, module} ->
        {source, text} =
          module_source(module, sources) || Mix.raise("missing poller source for #{module}")

        interval =
          case Regex.run(~r/def interval, do: ([^\n]+)/, text) do
            [_, value] -> value
            _ -> "not declared"
          end

        %{
          "id" => "poller:#{module}",
          "source" => source,
          "producer_scheduler" =>
            if(key == "yandex_rating",
              do: "Poller registry only; no cron entry and targets=[]",
              else: "config/config.exs cron -> Poller.Worker via registry key #{key}"
            ),
          "worker_process" => module,
          "frequency" => interval,
          "disposition" => "retain provider poller in Settings / Integrations"
        }
      end)

    expected =
      Enum.map(entries, & &1["id"])
      |> Enum.filter(
        &(String.starts_with?(&1, "worker:") or String.starts_with?(&1, "optional:"))
      )

    expected = Enum.sort(expected ++ Enum.map(pollers, & &1["id"]))
    actual = semantics |> Map.keys() |> Enum.sort()

    if expected != actual,
      do:
        Mix.raise(
          "background semantic annotations differ: missing #{inspect(expected -- actual)}, stale #{inspect(actual -- expected)}"
        )

    Enum.map(entries ++ pollers, fn entry ->
      id = background_semantic_id(entry)
      {external_call, gate, disable, obligation} = Map.fetch!(semantics, id)

      if Enum.any?([external_call, gate, disable, obligation], &(&1 in [nil, ""])),
        do: Mix.raise("incomplete background semantics for #{id}")

      entry
      |> Map.put("external_call", external_call)
      |> Map.put("enable_gate", gate)
      |> Map.put("on_disable", disable)
      |> Map.put("in_flight_obligation", obligation)
    end)
    |> Enum.sort_by(& &1["id"])
  end

  defp background_semantic_id(%{"id" => "cron:" <> rest, "worker_process" => worker}) do
    suffix = rest |> String.split(":") |> Enum.at(1)

    if worker == "Delivest.Integrations.Poller.Worker" and Map.has_key?(@poller_keys, suffix),
      do: "poller:#{Map.fetch!(@poller_keys, suffix)}",
      else: "worker:#{worker}"
  end

  defp background_semantic_id(%{"id" => id}), do: id

  defp line_at(source, offset) do
    source |> binary_part(0, offset) |> String.split("\n") |> length()
  end

  defp summary(inventory) do
    counts =
      for key <- ~w(screens fields actions features_integrations background),
          into: %{},
          do: {key, length(inventory[key])}

    controls = Enum.filter(inventory["actions"], &String.starts_with?(&1["id"], "control:"))
    no_receiver = Enum.filter(controls, &(&1["handler_clauses"] == []))

    receiver_note =
      case no_receiver do
        [] ->
          ""

        missing ->
          " #{Enum.map_join(missing, "; ", &"`#{&1["source"]}` #{&1["event"]}")} has no receiver in `lib/delivest_web` or `assets/js` according to repository search."
      end

    """
    # Staff administration source inventory

    Generated by `mix admin.inventory --write`; verify drift with `mix admin.inventory --check`.
    The machine-readable [inventory](inventory.json) contains stable IDs, source anchors, destinations and the required contract columns.

    | Register | Entries |
    | --- | ---: |
    | Screens | #{counts["screens"]} |
    | Staff form controls | #{counts["fields"]} |
    | Actions (handler clauses and controls) | #{counts["actions"]} |
    | Features/integrations | #{counts["features_integrations"]} |
    | Background jobs | #{counts["background"]} |

    The separate schema census has #{length(inventory["schema_census"])} declarations. It guards source drift; only staff controls receive editor assignments. The #{length(inventory["service_routes"])} service, authentication and internal routes are outside the four page types. The foundation gallery is an internal dev/test fixture and is excluded from controls and actions.

    #{length(controls) - length(no_receiver)}/#{length(controls)} literal event controls have a source handler candidate.#{receiver_note} The hook receiver for `acknowledge_cancel` and `crm_alert` is `DelivestWeb.Hooks.NewOrders`.

    ## Evidence and limits

    This is a source inventory, not a runtime audit. The reviewed [form owner map](form-owners.exs) assigns domain owner, canonical editor and target section for every staff form source. The [background semantics map](background-semantics.exs) records worker, optional calculation and provider poller gates and obligations. The generator extracts route session hooks, module permission references, schema defaults and literal validation calls. Those references do not prove every action is authorized at runtime, and a conditional validation call does not prove unconditional requiredness. Literal HTML names and dynamic name/field expressions are recorded with source anchors. Handler clauses establish event existence, not button visibility or a successful operation. Cron and worker declarations do not prove safe cancellation of in-flight work.

    Schema linkage uses the explicit owner map, including branch form and nested CRM provider settings. Controls with no direct schema field are virtual parameters, embedded fields or context inputs; their owner is the owning operation from the map. No configuration values, credentials or business data are included.

    ## Drift check

    `--check` rebuilds all five registers from the source tree and compares both artifacts byte-for-byte. A new form source without an owner annotation, a stale annotation, or a missing canonical file fails even during `--write`. New or removed routes, fields, events, features, optional tasks, cron entries and workers change the snapshot. Source line movement also changes anchors. Review the generated diff rather than accepting it automatically.
    """
  end
end
