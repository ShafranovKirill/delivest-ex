defmodule Delivest.Net.ProductOperations do
  @moduledoc "Preview and atomically apply local catalog workbook rows and branch copies."
  require Logger
  import Ecto.Query
  alias Delivest.{Audit, Identity, Money, Relations, Repo}

  alias Delivest.Net.{
    Category,
    Catalogs,
    ModifierGroup,
    Modifiers,
    Product,
    ProductModifierGroup,
    ProductOperationMapping,
    ProductWorkbook,
    SharedOwnership
  }

  alias Delivest.Media.File, as: MediaFile

  @fields ~w(name description quantity weight measure_unit is_active calories proteins fats carbohydrates excise vat tags suggested stars_price stars_reward category_id media_id)
  @int_fields ~w(quantity weight stars_price stars_reward)
  @float_fields ~w(calories proteins fats carbohydrates)
  @bool_fields ~w(is_active suggested)

  def export(staff, branch_id) do
    with :ok <- Identity.authorize(staff, "products.read", branch_id) do
      ids = Relations.list_target_ids("Branch", branch_id, "Product")

      rows =
        Product
        |> where([p], p.id in ^ids and is_nil(p.deleted_at))
        |> order_by([p], asc: p.name)
        |> Repo.all()

      ProductWorkbook.encode(Enum.map(rows, &export_row/1))
    end
  end

  def copy_preview(staff, selection, source_id, target_id) do
    with :ok <- Identity.authorize(staff, "products.read", source_id),
         :ok <- Identity.authorize(staff, "products.create", target_id),
         :ok <- target_menu_guard(target_id),
         :ok <- different(source_id, target_id) do
      ids = Relations.list_target_ids("Branch", source_id, "Product")

      query =
        from p in Product, where: p.id in ^ids and is_nil(p.deleted_at), order_by: [asc: p.name]

      query = if selection == :all, do: query, else: where(query, [p], p.id in ^selection)

      rows =
        Repo.all(query)
        |> Enum.with_index(1)
        |> Enum.map(fn {product, line} ->
          %{line: line, values: export_row(product), source_version: fingerprint(product)}
        end)

      preview(staff, target_id, rows, source_id)
    end
  end

  def import_preview(staff, target_id, binary) do
    with :ok <- Identity.authorize(staff, "products.create", target_id),
         :ok <- target_menu_guard(target_id),
         {:ok, rows} <- ProductWorkbook.decode(binary) do
      preview(staff, target_id, rows, nil)
    end
  end

  def apply_changes(
        staff,
        %{branch_id: branch_id, rows: rows, source_branch_id: source_id} = preview,
        choices \\ %{}
      ) do
    with :ok <- Identity.authorize(staff, "products.create", branch_id),
         :ok <- target_menu_guard(branch_id),
         :ok <- source_access(staff, source_id),
         {:ok, fresh} <-
           preview(
             staff,
             branch_id,
             Enum.map(rows, &Map.take(&1, [:line, :values, :source_version])),
             source_id
           ),
         :ok <- unchanged?(preview, fresh) do
      Repo.transaction(fn ->
        Repo.query!("SELECT pg_advisory_xact_lock(hashtext($1))", [
          "product-operations:" <> branch_id
        ])

        lock_ids =
          (Enum.map(rows, & &1.target_id) ++
             if(source_id, do: Enum.map(rows, & &1.values["source_key"]), else: []))
          |> Enum.reject(&is_nil/1)
          |> Enum.filter(&match?({:ok, _}, Ecto.UUID.cast(&1)))
          |> Enum.uniq()
          |> Enum.sort()

        Repo.all(from p in Product, where: p.id in ^lock_ids, order_by: p.id, lock: "FOR UPDATE")

        case preview(
               staff,
               branch_id,
               Enum.map(rows, &Map.take(&1, [:line, :values, :source_version])),
               source_id
             ) do
          {:ok, locked} ->
            if unchanged?(preview, locked) != :ok, do: Repo.rollback(:stale_preview)

            summary =
              Enum.reduce(locked.rows, %{created: 0, updated: 0, skipped: 0}, fn row, acc ->
                choice = Map.get(choices, row.values["source_key"], "skip")

                case apply_row(staff, branch_id, row, choice) do
                  {:ok, status} -> Map.update!(acc, status, &(&1 + 1))
                  {:error, error} -> Repo.rollback({:row, row.line, error})
                end
              end)

            if summary.created + summary.updated > 0 do
              Catalogs.bump_versions([branch_id])

              branch = Repo.get!(Delivest.Identity.Branch, branch_id)

              case Audit.record(staff, "product.bulk_applied", branch,
                     branch_id: branch_id,
                     publish: false,
                     metadata: %{
                       operation_type: if(source_id, do: "copy", else: "import"),
                       source_branch_id: source_id,
                       created: summary.created,
                       updated: summary.updated,
                       skipped: summary.skipped
                     }
                   ) do
                {:ok, event} -> {summary, event}
                {:error, reason} -> Repo.rollback(reason)
              end
            else
              {summary, nil}
            end

          error ->
            Repo.rollback(error)
        end
      end)
      |> case do
        {:ok, {summary, event}} ->
          if event, do: notify_after_commit(event, branch_id)
          {:ok, summary}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp notify_after_commit(event, branch_id) do
    safe_notify(fn -> Audit.publish(event) end)
    safe_notify(fn -> Catalogs.invalidate_menu_cache(branch_id) end)
    safe_notify(fn -> Cachex.clear(:cart_cache) end)
  end

  defp safe_notify(fun) do
    fun.()
  rescue
    error -> Logger.warning("product operation notification failed: #{Exception.message(error)}")
  catch
    :exit, reason -> Logger.warning("product operation notification exited: #{inspect(reason)}")
  end

  def copy(staff, selection, source_id, target_id) do
    with {:ok, preview} <- copy_preview(staff, selection, source_id, target_id),
         {:ok, summary} <- apply_changes(staff, preview) do
      {:ok, summary.created}
    end
  end

  defp preview(staff, branch_id, rows, source_id) do
    if length(rows) > 1000,
      do: {:error, :too_many_rows},
      else: do_preview(staff, branch_id, rows, source_id)
  end

  defp do_preview(staff, branch_id, rows, source_id) do
    keys = Enum.map(rows, & &1.values["source_key"])

    cond do
      length(keys) != length(Enum.uniq(keys)) ->
        {:error, :duplicate_source_keys}

      true ->
        evaluated =
          Enum.map(rows, fn row ->
            case validate_row(staff, branch_id, source_id, row) do
              {:ok, attrs, group_ids, target} ->
                Map.merge(row, %{
                  source_branch_id: source_id,
                  attrs: attrs,
                  group_ids: group_ids,
                  target_id: target && target.id,
                  target_version: target && fingerprint(target),
                  update_allowed: target && update_allowed?(staff, branch_id, target),
                  status: if(target, do: :match, else: :new),
                  errors: []
                })

              {:error, reason} ->
                Map.merge(row, %{
                  status: :error,
                  errors: [reason],
                  target_id: nil,
                  target_version: nil
                })
            end
          end)

        {:ok,
         %{
           branch_id: branch_id,
           source_branch_id: source_id,
           rows: evaluated,
           counts: Enum.frequencies_by(evaluated, & &1.status)
         }}
    end
  end

  defp validate_row(staff, branch_id, source_id, %{values: values} = row) do
    with :ok <- validate_source(source_id, values["source_key"], Map.get(row, :source_version)),
         {:ok, attrs} <- parse_values(values),
         {:ok, target} <- target_for(values["source_key"], branch_id),
         {:ok, _category} <- category_ref(staff, branch_id, source_id, attrs[:category_id], false),
         {:ok, groups} <- group_refs(staff, branch_id, values["modifier_group_ids"]),
         :ok <- media_ref(staff, source_id, attrs[:media_id]) do
      {:ok, attrs, groups, target}
    end
  end

  defp parse_values(values) do
    with true <-
           is_binary(values["source_key"]) and values["source_key"] != "" and
             byte_size(values["source_key"]) <= 128,
         {:ok, price} <- Money.parse(values["price_rub"]),
         {:ok, old_price} <- optional_money(values["old_price_rub"]),
         {:ok, parsed} <-
           Enum.reduce_while(@fields, {:ok, %{}}, fn key, {:ok, acc} ->
             case parse_field(key, values[key]) do
               {:ok, value} -> {:cont, {:ok, Map.put(acc, String.to_existing_atom(key), value)}}
               error -> {:halt, error}
             end
           end) do
      attrs = Map.merge(parsed, %{price: price, old_price: old_price})

      case Product.changeset(%Product{}, attrs) do
        %{valid?: true} -> {:ok, attrs}
        _ -> {:error, :invalid_product_fields}
      end
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_product_fields}
    end
  end

  defp parse_field("measure_unit", ""), do: {:error, :missing_measure_unit}

  defp parse_field(key, value) when key in @bool_fields do
    case value do
      "true" -> {:ok, true}
      "false" -> {:ok, false}
      _ -> {:error, :invalid_boolean}
    end
  end

  defp parse_field(key, value) when key in @int_fields do
    if value in [nil, ""] do
      {:ok, nil}
    else
      case Integer.parse(to_string(value)) do
        {int, ""} -> {:ok, int}
        _ -> {:error, :invalid_integer}
      end
    end
  end

  defp parse_field(key, value) when key in @float_fields do
    if value in [nil, ""] do
      {:ok, nil}
    else
      case Float.parse(to_string(value)) do
        {float, ""} -> {:ok, float}
        _ -> {:error, :invalid_number}
      end
    end
  end

  defp parse_field("tags", value) when value in [nil, ""], do: {:ok, []}

  defp parse_field("tags", value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, tags} when is_list(tags) ->
        if Enum.all?(tags, &is_binary/1), do: {:ok, tags}, else: {:error, :invalid_tags}

      _ ->
        {:error, :invalid_tags}
    end
  end

  defp parse_field(_key, ""), do: {:ok, nil}
  defp parse_field(_key, value), do: {:ok, value}
  defp optional_money(value) when value in [nil, ""], do: {:ok, nil}
  defp optional_money(value), do: Money.parse(value)

  defp target_for(key, branch_id) do
    case Repo.one(
           from m in ProductOperationMapping,
             where:
               m.source_key == ^key and m.target_branch_id == ^branch_id and
                 m.entity_type == "product"
         ) do
      nil ->
        if match?({:ok, _}, Ecto.UUID.cast(key)) and
             Relations.related?("Branch", branch_id, "Product", key) do
          case Repo.get(Product, key) do
            %Product{deleted_at: nil} = target -> {:ok, target}
            %Product{} -> {:error, :deleted_target}
            nil -> {:error, :stale_mapping}
          end
        else
          {:ok, nil}
        end

      mapping ->
        target = Repo.get(Product, mapping.target_entity_id)

        if mapping.target_entity_id != key and match?({:ok, _}, Ecto.UUID.cast(key)) and
             Relations.related?("Branch", branch_id, "Product", key) do
          {:error, :ambiguous_mapping}
        else
          if target && is_nil(target.deleted_at) &&
               Relations.related?("Branch", branch_id, "Product", target.id),
             do: {:ok, target},
             else: {:error, :stale_mapping}
        end
    end
  end

  defp validate_target(staff, branch_id, target) do
    if update_allowed?(staff, branch_id, target),
      do: :ok,
      else: {:error, :shared_or_forbidden_target}
  end

  defp category_ref(_staff, _branch_id, _source_id, nil, _create?), do: {:ok, nil}

  defp category_ref(staff, branch_id, source_id, category_id, create?) do
    cond do
      Relations.related?("Branch", branch_id, "Category", category_id) ->
        {:ok, category_id}

      source_id && Relations.related?("Branch", source_id, "Category", category_id) &&
          Identity.authorize(staff, "categories.read", source_id) == :ok ->
        clone_category(staff, branch_id, category_id, create?)

      is_nil(source_id) && match?({:ok, _}, Ecto.UUID.cast(category_id)) &&
        Repo.get(Category, category_id) &&
          Enum.any?(
            SharedOwnership.branches("Category", category_id),
            &(Identity.authorize(staff, "categories.read", &1) == :ok)
          ) ->
        clone_category(staff, branch_id, category_id, create?)

      true ->
        {:error, :invalid_category_reference}
    end
  end

  defp clone_category(staff, branch_id, source_id, false) do
    case clone_category_preview(branch_id, source_id) do
      {:ok, :new_category} ->
        if Identity.authorize(staff, "categories.create", branch_id) == :ok,
          do: {:ok, :new_category},
          else: {:error, :forbidden_category}

      other ->
        other
    end
  end

  defp clone_category(staff, branch_id, source_id, true) do
    case clone_category(staff, branch_id, source_id, false) do
      {:ok, :new_category} ->
        if Identity.authorize(staff, "categories.create", branch_id) == :ok do
          source = Repo.get!(Category, source_id)

          with {:ok, copy} <-
                 Category.changeset(%Category{}, Map.take(source, [:name, :order, :is_active]))
                 |> Repo.insert(),
               {:ok, _} <-
                 Relations.create_relation(Repo, "Branch", branch_id, "Category", copy.id),
               {:ok, _} <- map_source(source_id, branch_id, "category", copy.id) do
            {:ok, copy.id}
          end
        else
          {:error, :forbidden}
        end

      other ->
        other
    end
  end

  defp clone_category_preview(branch_id, source_id) do
    case Repo.one(
           from m in ProductOperationMapping,
             where:
               m.source_key == ^source_id and m.target_branch_id == ^branch_id and
                 m.entity_type == "category"
         ) do
      nil ->
        {:ok, :new_category}

      mapping ->
        if Relations.related?("Branch", branch_id, "Category", mapping.target_entity_id),
          do: {:ok, mapping.target_entity_id},
          else: {:error, :stale_category_mapping}
    end
  end

  defp group_refs(_staff, _branch_id, value) when value in [nil, ""], do: {:ok, []}

  defp group_refs(staff, branch_id, value) when is_binary(value) do
    ids = String.split(value, ",", trim: true) |> Enum.map(&String.trim/1)

    cond do
      Identity.authorize(staff, "products.read", branch_id) != :ok ->
        {:error, :forbidden_modifier_reference}

      length(ids) == length(Enum.uniq(ids)) and
          Enum.all?(
            ids,
            &(match?({:ok, _}, Ecto.UUID.cast(&1)) and Repo.get(ModifierGroup, &1) != nil)
          ) ->
        {:ok, ids}

      true ->
        {:error, :invalid_modifier_reference}
    end
  end

  defp group_refs(_, _, _), do: {:error, :invalid_modifier_reference}

  defp media_ref(_staff, _source_id, nil), do: :ok

  defp media_ref(staff, source_id, media_id) do
    file = if match?({:ok, _}, Ecto.UUID.cast(media_id)), do: Repo.get(MediaFile, media_id)

    accessible_branches =
      if source_id do
        [source_id]
      else
        staff
        |> Identity.list_branch_for_staff()
        |> Enum.filter(&(Identity.authorize(staff, "products.read", &1.id) == :ok))
        |> Enum.map(& &1.id)
      end

    product_ids =
      Enum.flat_map(accessible_branches, &Relations.list_target_ids("Branch", &1, "Product"))

    attached? =
      product_ids != [] and
        Repo.exists?(from p in Product, where: p.id in ^product_ids and p.media_id == ^media_id)

    if file && file.context == :product && not file.is_private &&
         (attached? or file.owner_id == staff.id),
       do: :ok,
       else: {:error, :invalid_media_reference}
  end

  defp apply_row(_staff, _branch_id, %{status: :error, errors: errors}, _choice),
    do: {:error, errors}

  defp apply_row(_staff, _branch_id, %{status: :match}, "skip"), do: {:ok, :skipped}

  defp apply_row(staff, branch_id, %{status: :match, target_id: id} = row, "update") do
    with :ok <- validate_target(staff, branch_id, Repo.get!(Product, id)),
         {:ok, attrs} <- resolved_attrs(staff, branch_id, row),
         {:ok, _} <- Product.changeset(Repo.get!(Product, id), attrs) |> Repo.update(),
         :ok <- replace_groups(id, row.group_ids) do
      {:ok, :updated}
    end
  end

  defp apply_row(_staff, _branch_id, %{status: :match}, _), do: {:error, :invalid_choice}

  defp apply_row(staff, branch_id, %{status: :new} = row, _choice) do
    with {:ok, attrs} <- resolved_attrs(staff, branch_id, row),
         attrs = Map.put(attrs, :slug, unique_slug(attrs.name)),
         {:ok, product} <- Product.changeset(%Product{}, attrs) |> Repo.insert(),
         {:ok, _} <- Relations.create_relation(Repo, "Branch", branch_id, "Product", product.id),
         {:ok, _} <- map_source(row.values["source_key"], branch_id, "product", product.id),
         :ok <- replace_groups(product.id, row.group_ids) do
      {:ok, :created}
    end
  end

  defp resolved_attrs(staff, branch_id, row) do
    case category_ref(staff, branch_id, row.source_branch_id, row.attrs.category_id, true) do
      {:ok, id} -> {:ok, Map.put(row.attrs, :category_id, id)}
      error -> error
    end
  end

  defp replace_groups(product_id, ids) do
    Repo.delete_all(from l in ProductModifierGroup, where: l.product_id == ^product_id)

    rows =
      ids
      |> Enum.with_index()
      |> Enum.map(fn {id, index} -> %{product_id: product_id, group_id: id, position: index} end)

    Repo.insert_all(ProductModifierGroup, rows)
    :ok
  end

  defp map_source(source, branch, type, target) do
    %ProductOperationMapping{}
    |> ProductOperationMapping.changeset(%{
      source_key: source,
      target_branch_id: branch,
      entity_type: type,
      target_entity_id: target
    })
    |> Repo.insert()
  end

  defp unique_slug(name) do
    base = Delivest.Slug.slugify(name) || "product"

    Delivest.Slug.unique(base, fn slug ->
      Repo.exists?(from p in Product, where: p.slug == ^slug)
    end)
  end

  defp unchanged?(old, fresh) do
    identity = fn preview ->
      Enum.map(
        preview.rows,
        &{&1.values["source_key"], &1.status, &1.target_id, &1.target_version, &1.errors}
      )
    end

    if identity.(old) == identity.(fresh), do: :ok, else: {:error, :stale_preview}
  end

  defp source_access(_staff, nil), do: :ok
  defp source_access(staff, id), do: Identity.authorize(staff, "products.read", id)

  defp update_allowed?(staff, branch_id, target),
    do:
      SharedOwnership.branches("Product", target.id) == [branch_id] and
        Identity.authorize(staff, "products.update", branch_id) == :ok

  defp target_menu_guard(branch_id) do
    branch =
      if match?({:ok, _}, Ecto.UUID.cast(branch_id)) do
        case Repo.get(Delivest.Identity.Branch, branch_id) do
          nil -> nil
          branch -> Repo.preload(branch, :info)
        end
      end

    if branch && Delivest.Gateway.own?(branch, :menu),
      do: :ok,
      else: {:error, :crm_owned_menu}
  end

  defp different(id, id), do: {:error, :same_branch}
  defp different(_, _), do: :ok

  defp validate_source(nil, _key, _version), do: :ok

  defp validate_source(source_id, key, version) do
    product = Repo.get(Product, key)

    if product && is_nil(product.deleted_at) &&
         Relations.related?("Branch", source_id, "Product", key) &&
         fingerprint(product) == version, do: :ok, else: {:error, :stale_source}
  end

  defp fingerprint(product) do
    data =
      {Map.take(product, [
         :name,
         :price,
         :old_price,
         :description,
         :quantity,
         :weight,
         :measure_unit,
         :calories,
         :proteins,
         :fats,
         :carbohydrates,
         :excise,
         :vat,
         :is_active,
         :tags,
         :suggested,
         :stars_price,
         :stars_reward,
         :category_id,
         :media_id
       ]), Modifiers.group_ids(product.id),
       SharedOwnership.branches("Product", product.id) |> Enum.sort()}

    :crypto.hash(:sha256, :erlang.term_to_binary(data))
  end

  defp export_row(product) do
    Map.new(ProductWorkbook.headers(), fn key ->
      value =
        case key do
          "schema_version" -> "delivest-products-v1"
          "source_key" -> product.id
          "price_rub" -> Money.input(product.price)
          "old_price_rub" -> Money.input(product.old_price)
          "modifier_group_ids" -> Enum.join(Modifiers.group_ids(product.id), ",")
          "tags" -> Jason.encode!(product.tags || [])
          field -> Map.get(product, String.to_existing_atom(field))
        end

      {key,
       if(is_atom(value) and not is_nil(value),
         do: Atom.to_string(value),
         else: to_string(value || "")
       )}
    end)
  end
end
