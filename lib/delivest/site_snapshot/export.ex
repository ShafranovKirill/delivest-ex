defmodule Delivest.SiteSnapshot.Export do
  @moduledoc "Reads a consistent snapshot of one branch or of the whole franchise."

  import Ecto.Query

  alias Delivest.{Delivery, Media, Relations, Repo}
  alias Delivest.Franchise.LegalDocument
  alias Delivest.Franchise.Settings, as: FranchiseSettings
  alias Delivest.Identity.Branch
  alias Delivest.Media.File, as: MediaFile

  alias Delivest.Net.{
    Category,
    Modifier,
    ModifierGroup,
    Product,
    ProductExternalId,
    ProductModifierGroup,
    ProductTag
  }

  alias Delivest.SiteSnapshot.Fields

  @max_branches 100

  def branch_data(branch_id) do
    Repo.transaction(fn ->
      maybe_repeatable_read!()
      build_snapshot(branch_id, Fields.sections(), :branch)
    end)
  end

  def franchise_data(sections) do
    Repo.transaction(fn ->
      maybe_repeatable_read!()

      branches =
        Repo.all(from b in Branch, where: is_nil(b.deleted_at), order_by: [asc: b.inserted_at])

      if length(branches) > @max_branches, do: Repo.rollback(:too_many_branches)

      data = %{
        "public_bucket" => Media.public_bucket(),
        "sections" => Enum.map(sections, &Atom.to_string/1),
        "branches" => Enum.map(branches, &build_snapshot(&1.id, sections, :franchise))
      }

      data =
        if :franchise in sections do
          franchise = Repo.one(FranchiseSettings) || %FranchiseSettings{}

          Map.merge(data, %{
            "franchise" => Fields.fields(franchise, Fields.franchise_fields(sections)),
            "documents" => custom_documents()
          })
        else
          data
        end

      if :integrations in sections,
        do: Map.put(data, "integrations", global_integrations()),
        else: data
    end)
  end

  defp maybe_repeatable_read! do
    # The test sandbox already owns the surrounding transaction.
    if Repo.config()[:pool] != Ecto.Adapters.SQL.Sandbox do
      Repo.query!("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ")
    end
  end

  defp build_snapshot(branch_id, sections, mode) do
    branch = Repo.get!(Branch, branch_id) |> Repo.preload(:info)

    branch_fields = Fields.branch_fields(mode)

    data = %{
      "branch_id" => branch_id,
      "branch" => Fields.fields(branch, branch_fields)
    }

    data =
      if mode == :branch,
        do: Map.put(data, "public_bucket", Media.public_bucket()),
        else: data

    data =
      if mode == :branch or :storefront in sections do
        delivery_settings = Delivery.get_settings(branch_id)
        zones = Delivery.list_zones(branch_id)

        Map.merge(data, %{
          "info" => Fields.info(branch.info),
          "delivery_settings" =>
            Map.put(
              Fields.fields(delivery_settings, Fields.settings_fields()),
              "thresholds",
              Fields.thresholds(delivery_settings.thresholds)
            ),
          "zones" =>
            Enum.map(zones, fn zone ->
              Map.merge(Fields.record(zone, Fields.zone_fields()), %{
                "thresholds" => Fields.thresholds(zone.thresholds)
              })
            end)
        })
      else
        data
      end

    data =
      if mode == :branch or :catalog in sections,
        do: Map.merge(data, catalog_snapshot(branch_id)),
        else: data

    data =
      if mode == :franchise and :integrations in sections,
        do: Map.put(data, "integrations", Fields.branch_integrations(branch.info)),
        else: data

    if mode == :branch do
      franchise = Repo.one(FranchiseSettings) || %FranchiseSettings{}
      Map.put(data, "franchise", Fields.fields(franchise, Fields.franchise_fields(sections)))
    else
      data
    end
  end

  defp catalog_snapshot(branch_id) do
    category_ids = Relations.list_target_ids("Branch", branch_id, "Category")
    product_ids = Relations.list_target_ids("Branch", branch_id, "Product")
    categories = Repo.all(from c in Category, where: c.id in ^category_ids)

    products =
      Repo.all(from p in Product, where: p.id in ^product_ids and is_nil(p.deleted_at))

    group_ids =
      Repo.all(
        from l in ProductModifierGroup,
          where: l.product_id in ^product_ids,
          select: l.group_id
      )

    groups = Repo.all(from g in ModifierGroup, where: g.id in ^group_ids)
    modifiers = Repo.all(from m in Modifier, where: m.group_id in ^group_ids)
    links = Repo.all(from l in ProductModifierGroup, where: l.product_id in ^product_ids)
    media_ids = products |> Enum.map(& &1.media_id) |> Enum.reject(&is_nil/1)
    media = Repo.all(from m in MediaFile, where: m.id in ^media_ids)
    tag_ids = products |> Enum.flat_map(&(&1.tags || [])) |> Enum.uniq()
    tags = Repo.all(from t in ProductTag, where: t.id in ^tag_ids)

    catalog = %{
      "categories" =>
        Enum.map(categories, &Fields.record(&1, Fields.catalog_fields("categories"))),
      "products" =>
        Enum.map(products, fn product ->
          Map.merge(Fields.record(product, Fields.catalog_fields("products")), %{
            "category_id" => product.category_id,
            "media_id" => product.media_id
          })
        end),
      "groups" => Enum.map(groups, &Fields.record(&1, Fields.catalog_fields("groups"))),
      "modifiers" =>
        Enum.map(modifiers, fn modifier ->
          Map.put(
            Fields.record(modifier, Fields.catalog_fields("modifiers")),
            "group_id",
            modifier.group_id
          )
        end),
      "links" =>
        Enum.map(
          links,
          &%{
            "product_id" => &1.product_id,
            "group_id" => &1.group_id,
            "position" => &1.position
          }
        ),
      "media" => Enum.map(media, &Fields.record(&1, Fields.catalog_fields("media"))),
      "tags" => Enum.map(tags, &Fields.record(&1, Fields.catalog_fields("tags")))
    }

    Map.put(catalog, "frontpad_ids", frontpad_ids(branch_id, catalog))
  end

  defp frontpad_ids(branch_id, catalog) do
    Enum.flat_map(Fields.frontpad_catalog_types(), fn {entity_type, collection} ->
      ids = Enum.map(catalog[collection], & &1["id"])

      Repo.all(
        from e in ProductExternalId,
          where:
            e.branch_id == ^branch_id and e.provider == "frontpad" and
              e.entity_type == ^entity_type and e.entity_id in ^ids,
          order_by: e.entity_id,
          select: %{
            "entity_type" => e.entity_type,
            "entity_id" => e.entity_id,
            "external_id" => e.external_id
          }
      )
    end)
  end

  defp custom_documents do
    Repo.all(LegalDocument)
    |> Enum.map(&%{"kind" => to_string(&1.kind), "body" => &1.body})
  end

  defp global_integrations do
    integrations =
      Fields.global_integrations()
      |> Enum.reject(fn {_key, module, _fields} -> module == FranchiseSettings end)
      |> Enum.flat_map(fn {key, module, fields} ->
        with %{} = settings <- Repo.one(module),
             attrs = settings |> Map.take(fields) |> Jason.encode!() |> Jason.decode!(),
             %{valid?: true} <- module.changeset(struct(module), attrs) do
          [{key, attrs}]
        else
          _ -> []
        end
      end)
      |> Map.new()

    franchise = Repo.one(FranchiseSettings) || %FranchiseSettings{}

    rating =
      Fields.franchise_integration_fields()
      |> Map.new(&{to_string(&1), Map.get(franchise, &1)})

    if Enum.all?(rating, fn {_key, value} -> is_nil(value) or value == "" end),
      do: integrations,
      else: Map.put(integrations, "yandex_rating", rating)
  end
end
