defmodule Delivest.SiteSnapshot.ImportPlan do
  @moduledoc """
  Turns validated archive data into one import plan: target branches, entity
  mappings, relations, media references and post-commit actions.

  The plan is built and checked under the global import lock before any S3
  write. `preflight!/1` is run again after the upload, because normal admin
  activity can change ownership while files are being stored.
  """

  import Ecto.Query

  alias Delivest.{Repo, Relations}
  alias Delivest.Delivery.Zone
  alias Delivest.Identity.Branch
  alias Delivest.Media.File, as: MediaFile

  alias Delivest.Net.{
    Category,
    Modifier,
    ModifierGroup,
    Product,
    ProductModifierGroup,
    ProductTag
  }

  alias Delivest.Relations.EntityRelation
  alias Delivest.SiteSnapshot.{Branches, Fields, Mapping}

  @catalog_order ~w(categories groups media tags products modifiers)

  def build_branch(manifest, branch_id, data) do
    entry = %{
      source_id: data["branch_id"],
      target_id: branch_id,
      data: data,
      membership: membership(data, Fields.sections())
    }

    finish(
      :branch,
      Fields.sections(),
      [entry],
      %{data["branch_id"] => branch_id},
      manifest,
      %{
        branches_created: 0,
        branches_updated: 1
      },
      data["public_bucket"]
    )
    |> Map.put(:franchise, data["franchise"])
  end

  def build_franchise(manifest, data, sections) do
    {branches, counts} = prepare_branches!(manifest, data)

    entries =
      Enum.map(data["branches"], fn entry ->
        %{
          source_id: entry["branch_id"],
          target_id: Map.fetch!(branches, entry["branch_id"]),
          data: entry,
          membership: membership(entry, sections)
        }
      end)

    finish(:franchise, sections, entries, branches, manifest, counts, data["public_bucket"])
    |> Map.merge(%{
      franchise: data["franchise"],
      documents: data["documents"],
      integrations: data["integrations"]
    })
  end

  def preflight!(plan) do
    target_ids = MapSet.new(Map.values(plan.branches))

    Enum.each(plan.catalog, fn {type, entries} ->
      schema = Fields.catalog_schemas()[type]

      Enum.each(entries, fn {_source_id, target_id} ->
        assert_target_ownership!(type, schema, target_id, target_ids)
      end)
    end)

    Enum.each(plan.entries, &assert_zones!(&1.data, &1.target_id))
    plan
  end

  defp finish(scope, sections, entries, branches, manifest, counts, public_bucket) do
    target_ids = MapSet.new(Map.values(branches))
    grouped = collect_catalog(entries, sections)
    {catalog, catalog_counts} = resolve_catalog(manifest, grouped, branches, target_ids)
    links = resolve_links(entries, catalog)

    remapped =
      Enum.map(entries, fn entry ->
        data =
          entry.data
          |> then(fn value ->
            if :catalog in sections, do: remap_catalog(value, catalog), else: value
          end)
          |> then(fn value ->
            if :storefront in sections, do: remap_zones(value, catalog), else: value
          end)

        %{entry | data: data}
      end)

    plan = %{
      scope: scope,
      sections: sections,
      public_bucket: public_bucket,
      branches: branches,
      entries: remapped,
      catalog: catalog,
      links: links,
      media_ids:
        catalog
        |> Map.get("media", %{})
        |> Map.values()
        |> Enum.uniq(),
      counts: Map.merge(counts, catalog_counts)
    }

    preflight!(plan)
  end

  defp membership(entry, sections) do
    types =
      if :catalog in sections, do: ~w(categories products), else: []

    Map.new(types, fn type -> {type, MapSet.new(Enum.map(entry[type] || [], & &1["id"]))} end)
  end

  defp prepare_branches!(manifest, data) do
    source = manifest["source_installation"]

    {branches, counts, _used} =
      Enum.reduce(
        data["branches"],
        {%{}, %{branches_created: 0, branches_updated: 0}, MapSet.new()},
        fn entry, {branches, counts, used} ->
          source_id = entry["branch_id"]
          attrs = entry["branch"]

          {branch, created?} =
            case Branches.find_target(source, source_id, attrs["slug"]) do
              nil -> {Branches.put!(%Branch{}, attrs), true}
              %Branch{} = branch -> {Branches.put!(branch, attrs), false}
            end

          if MapSet.member?(used, branch.id) do
            abort!({:ambiguous_branch, source_id, branch.id})
          end

          Branches.put_mapping!(source, branch.id, source_id)

          state = if created?, do: :branches_created, else: :branches_updated

          {Map.put(branches, source_id, branch.id), Map.update!(counts, state, &(&1 + 1)),
           MapSet.put(used, branch.id)}
        end
      )

    {branches, counts}
  end

  defp collect_catalog(entries, sections) do
    types =
      if :catalog in sections, do: @catalog_order, else: []

    types = if :storefront in sections, do: types ++ ["zones"], else: types
    schemas = Fields.catalog_schemas()

    Enum.reduce(entries, %{}, fn entry, grouped ->
      Enum.reduce(types, grouped, fn type, grouped ->
        Enum.reduce(entry.data[type] || [], grouped, fn item, grouped ->
          add_grouped(grouped, type, schemas[type], item, entry.source_id)
        end)
      end)
    end)
  end

  defp add_grouped(grouped, type, schema, item, branch_id) do
    source_id = item["id"]

    group =
      grouped
      |> Map.get(type, %{})
      |> Map.get(source_id, %{schema: schema, item: item, branches: MapSet.new()})

    cond do
      type == "zones" and MapSet.size(group.branches) > 0 and
          not MapSet.member?(group.branches, branch_id) ->
        abort!({:entity_conflict, type, source_id})

      not same_item?(type, group.item, item) ->
        abort!({:entity_conflict, type, source_id})

      true ->
        group = %{group | branches: MapSet.put(group.branches, branch_id)}
        Map.update(grouped, type, %{source_id => group}, &Map.put(&1, source_id, group))
    end
  end

  defp same_item?("products", left, right) do
    Map.put(left, "tags", Enum.sort(left["tags"] || [])) ==
      Map.put(right, "tags", Enum.sort(right["tags"] || []))
  end

  defp same_item?(_type, left, right), do: left == right

  defp resolve_catalog(manifest, grouped, branches, target_ids) do
    source = manifest["source_installation"]

    Enum.reduce(grouped, {%{}, %{created: 0, updated: 0}}, fn {type, entries},
                                                              {catalog, counts} ->
      {targets, counts} =
        Enum.reduce(entries, {%{}, counts}, fn {source_id, group}, {targets, counts} ->
          target_id = resolve_target(source, type, group, branches, target_ids, targets)

          group.branches
          |> Enum.each(fn branch_source ->
            put_catalog_mapping!(
              source,
              type,
              Map.fetch!(branches, branch_source),
              source_id,
              target_id
            )
          end)

          state = if Repo.get(group.schema, target_id), do: :updated, else: :created
          {Map.put(targets, source_id, target_id), Map.update!(counts, state, &(&1 + 1))}
        end)

      {Map.put(catalog, type, targets),
       Map.put(counts, String.to_existing_atom(type), map_size(targets))}
    end)
  end

  defp resolve_target(source, type, group, branches, target_ids, _resolved) do
    rows =
      Repo.all(
        from m in Mapping,
          where:
            m.source_installation_id == ^source and m.entity_type == ^type and
              m.source_id == ^group.item["id"]
      )

    targets = rows |> Enum.map(& &1.target_id) |> Enum.uniq()

    case targets do
      [target_id] ->
        assert_target_ownership!(type, group.schema, target_id, target_ids)
        target_id

      [_ | _] ->
        abort!(
          {:conflicting_mapping, type, group.item["id"], Enum.map(rows, & &1.target_branch_id)}
        )

      [] ->
        target_id = candidate_id(type, group, branches, target_ids)
        assert_target_ownership!(type, group.schema, target_id, target_ids)
        target_id
    end
  end

  defp candidate_id("zones", group, branches, _target_ids) do
    target_branch = branches |> Map.fetch!(Enum.at(group.branches, 0))

    case Repo.get(Zone, group.item["id"]) do
      %Zone{branch_id: ^target_branch} -> group.item["id"]
      _ -> Ecto.UUID.generate()
    end
  end

  defp candidate_id("products", group, _branches, target_ids) do
    item = group.item

    case product_slug_match(item["slug"]) do
      nil ->
        candidate_by_source_id("products", Product, item["id"], target_ids)

      %Product{id: id} ->
        if any_plan_branch?("Product", id, target_ids) do
          id
        else
          abort!({:shared_catalog_conflict, "Product", id})
        end
    end
  end

  defp candidate_id("categories", group, _branches, target_ids),
    do: candidate_by_source_id("categories", Category, group.item["id"], target_ids)

  defp candidate_id("groups", group, _branches, target_ids) do
    id = group.item["id"]

    case Repo.get(ModifierGroup, id) do
      nil ->
        id

      _existing ->
        if any_plan_branch?("groups", id, target_ids), do: id, else: Ecto.UUID.generate()
    end
  end

  defp candidate_id("modifiers", group, _branches, target_ids) do
    id = group.item["id"]

    case Repo.get(Modifier, id) do
      nil ->
        id

      _existing ->
        if any_plan_branch?("modifiers", id, target_ids), do: id, else: Ecto.UUID.generate()
    end
  end

  defp candidate_id("tags", group, _branches, target_ids) do
    id = group.item["id"]

    case Repo.get(ProductTag, id) do
      nil -> id
      _existing -> if any_plan_branch?("tags", id, target_ids), do: id, else: Ecto.UUID.generate()
    end
  end

  defp candidate_id("media", group, _branches, target_ids) do
    id = group.item["id"]

    case Repo.get(MediaFile, id) do
      nil ->
        id

      %MediaFile{owner_id: nil} ->
        id

      %MediaFile{owner_id: owner_id} ->
        if any_plan_branch?("Product", owner_id, target_ids), do: id, else: Ecto.UUID.generate()
    end
  end

  defp candidate_by_source_id(type, schema, source_id, target_ids) do
    case Repo.get(schema, source_id) do
      nil ->
        source_id

      _existing ->
        if any_plan_branch?(relation_type(type), source_id, target_ids),
          do: source_id,
          else: Ecto.UUID.generate()
    end
  end

  defp product_slug_match(slug) when is_binary(slug), do: Repo.get_by(Product, slug: slug)
  defp product_slug_match(_slug), do: nil

  defp relation_type("categories"), do: "Category"
  defp relation_type("products"), do: "Product"

  defp any_plan_branch?(type, id, target_ids) do
    type
    |> branch_ids(id)
    |> any_in?(target_ids)
  end

  defp any_in?(ids, target_ids), do: Enum.any?(ids, &MapSet.member?(target_ids, &1))

  defp branch_ids("zones", id) do
    case Repo.get(Zone, id) do
      %Zone{branch_id: branch_id} -> [branch_id]
      nil -> []
    end
  end

  defp branch_ids("categories", id), do: branch_ids("Category", id)
  defp branch_ids("products", id), do: branch_ids("Product", id)

  defp branch_ids("groups", id) do
    from(l in ProductModifierGroup,
      join: r in EntityRelation,
      on:
        r.to_id == l.product_id and r.to_entity_type == "Product" and
          r.from_entity_type == "Branch",
      where: l.group_id == ^id,
      select: r.from_id,
      distinct: true
    )
    |> Repo.all()
  end

  defp branch_ids("modifiers", id) do
    from(m in Modifier,
      join: l in ProductModifierGroup,
      on: l.group_id == m.group_id,
      join: r in EntityRelation,
      on:
        r.to_id == l.product_id and r.to_entity_type == "Product" and
          r.from_entity_type == "Branch",
      where: m.id == ^id,
      select: r.from_id,
      distinct: true
    )
    |> Repo.all()
  end

  defp branch_ids("tags", id) do
    from(p in Product,
      join: r in EntityRelation,
      on: r.to_id == p.id and r.to_entity_type == "Product" and r.from_entity_type == "Branch",
      where: ^id in p.tags,
      select: r.from_id,
      distinct: true
    )
    |> Repo.all()
  end

  defp branch_ids("media", id) do
    case Repo.get(MediaFile, id) do
      %MediaFile{owner_id: nil} -> []
      %MediaFile{owner_id: owner_id} -> branch_ids("Product", owner_id)
      nil -> []
    end
  end

  defp branch_ids(type, id) when type in ["Category", "Product"] do
    Relations.list_source_ids(type, id, "Branch")
  end

  defp assert_target_ownership!(type, _schema, target_id, target_ids) do
    owners = branch_ids(type, target_id) |> MapSet.new()

    if MapSet.subset?(owners, target_ids) do
      :ok
    else
      outside = MapSet.difference(owners, target_ids) |> MapSet.to_list()
      abort!({:shared_catalog_conflict, type, target_id, outside})
    end
  end

  defp put_catalog_mapping!(source, type, target_branch_id, source_id, target_id) do
    existing =
      Repo.get_by(Mapping,
        source_installation_id: source,
        target_branch_id: target_branch_id,
        entity_type: type,
        source_id: source_id
      )

    cond do
      existing && existing.target_id == target_id ->
        :ok

      existing ->
        abort!({:conflicting_mapping, type, source_id, [existing.target_id, target_id]})

      Repo.get_by(Mapping,
        source_installation_id: source,
        target_branch_id: target_branch_id,
        entity_type: type,
        target_id: target_id
      ) ->
        abort!({:conflicting_mapping, type, source_id, [target_branch_id]})

      true ->
        Repo.insert!(%Mapping{
          source_installation_id: source,
          target_branch_id: target_branch_id,
          entity_type: type,
          source_id: source_id,
          target_id: target_id
        })
    end
  end

  defp resolve_links(entries, catalog) do
    entries
    |> Enum.flat_map(fn entry -> entry.data["links"] || [] end)
    |> Enum.reduce(%{}, fn link, links ->
      key = {link["product_id"], link["group_id"]}

      case Map.fetch(links, key) do
        :error ->
          Map.put(links, key, link)

        {:ok, existing} ->
          if existing["position"] == link["position"] do
            links
          else
            abort!({:entity_conflict, "links", "#{elem(key, 0)}/#{elem(key, 1)}"})
          end
      end
    end)
    |> Enum.map(fn {_key, link} ->
      %{
        "product_id" => Map.fetch!(catalog["products"], link["product_id"]),
        "group_id" => Map.fetch!(catalog["groups"], link["group_id"]),
        "position" => link["position"]
      }
    end)
  end

  defp remap_catalog(data, catalog) do
    update = fn type, fun ->
      Enum.map(data[type] || [], fn item ->
        item
        |> Map.put("id", Map.fetch!(catalog, type) |> Map.fetch!(item["id"]))
        |> fun.()
      end)
    end

    data
    |> Map.put("categories", update.("categories", & &1))
    |> Map.put("groups", update.("groups", & &1))
    |> Map.put(
      "media",
      update.("media", fn item ->
        Map.update!(item, "owner_id", fn owner ->
          Map.get(catalog["products"] || %{}, owner, owner)
        end)
      end)
    )
    |> Map.put("tags", update.("tags", & &1))
    |> Map.put(
      "products",
      update.("products", fn item ->
        item
        |> Map.update!("category_id", &mapped_id(catalog, "categories", &1))
        |> Map.update!("media_id", &mapped_id(catalog, "media", &1))
        |> Map.update!("tags", fn tags ->
          Enum.map(tags || [], &mapped_id(catalog, "tags", &1))
        end)
      end)
    )
    |> Map.put(
      "modifiers",
      update.("modifiers", fn item ->
        Map.update!(item, "group_id", &mapped_id(catalog, "groups", &1))
      end)
    )
    |> Map.put("links", [])
  end

  defp remap_zones(data, catalog) do
    Map.update(data, "zones", [], fn zones ->
      Enum.map(zones, fn item ->
        Map.update!(item, "id", &Map.fetch!(catalog["zones"], &1))
      end)
    end)
  end

  defp mapped_id(_catalog, _type, nil), do: nil

  defp mapped_id(catalog, type, source_id),
    do: Map.fetch!(catalog, type) |> Map.fetch!(source_id)

  defp assert_zones!(data, target_branch_id) do
    Enum.each(data["zones"] || [], fn zone ->
      case Repo.get(Zone, zone["id"]) do
        %Zone{branch_id: ^target_branch_id} -> :ok
        nil -> :ok
        _ -> abort!(:zone_conflict)
      end
    end)
  end

  defp abort!(reason), do: throw({:snapshot_abort, reason})
end
