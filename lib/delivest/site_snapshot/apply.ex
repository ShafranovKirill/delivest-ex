defmodule Delivest.SiteSnapshot.Apply do
  @moduledoc """
  Applies an import plan inside its database transaction and runs the work that
  must happen only after a successful commit.
  """

  import Ecto.Query

  alias Delivest.{Delivery, Media, Relations, Repo}
  alias Delivest.Delivery.{Settings, Zone}
  alias Delivest.Franchise.LegalDocument
  alias Delivest.Franchise.Settings, as: FranchiseSettings
  alias Delivest.Identity.Branch
  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Integrations.Health
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

  alias Delivest.SiteSnapshot.{Branches, Fields, MediaTransfer}

  def apply(plan, uploaded) do
    apply_branches(plan)
    if :storefront in plan.sections, do: apply_storefront(plan)
    if :catalog in plan.sections, do: apply_catalog(plan, uploaded)
    if :integrations in plan.sections, do: apply_branch_integrations(plan)

    if :franchise in plan.sections do
      put_franchise(plan.franchise, uploaded, plan.public_bucket)
      put_documents(Map.get(plan, :documents))
    end

    if :integrations in plan.sections, do: put_global_integrations(Map.get(plan, :integrations))
  end

  def post_commit(plan) do
    branch_ids = plan.branches |> Map.values() |> Enum.uniq()

    case plan.scope do
      :branch ->
        Enum.each(branch_ids, &Delivest.Net.Catalogs.clear_menu_cache/1)
        Cachex.del(:branch_cache, List.first(branch_ids))

      :franchise ->
        Cachex.clear(:branch_cache)

        if :catalog in plan.sections,
          do: Enum.each(branch_ids, &Delivest.Net.Catalogs.clear_menu_cache/1)
    end

    Cachex.del(:franchise_cache, :settings)
    invalidate_integrations(branch_ids, plan.sections)
    enqueue_thumbnails(plan.media_ids)
    :ok
  end

  defp apply_branches(plan) do
    Enum.each(plan.entries, fn entry ->
      branch = Repo.get!(Branch, entry.target_id)

      Branches.put!(branch, entry.data["branch"], validate_conflicts: plan.scope == :franchise)
    end)
  end

  defp apply_storefront(plan) do
    Enum.each(plan.entries, fn entry ->
      put_info(entry.target_id, entry.data["info"])
      put_delivery(entry.target_id, entry.data)
    end)
  end

  defp apply_catalog(plan, uploaded) do
    entries = plan.entries

    Enum.each(unique_items(entries, "categories"), fn item ->
      put_identified(Category, item, Fields.catalog_fields("categories"), &Category.changeset/2)
    end)

    Enum.each(unique_items(entries, "groups"), fn item ->
      put_identified(
        ModifierGroup,
        item,
        Fields.catalog_fields("groups"),
        &ModifierGroup.changeset/2
      )
    end)

    Enum.each(unique_items(entries, "media"), &put_media(&1, uploaded))

    Enum.each(unique_items(entries, "tags"), fn item ->
      attrs =
        Map.put(item, "icon_key", mapped_key(item["icon_key"], uploaded, plan.public_bucket))

      put_identified(ProductTag, attrs, Fields.catalog_fields("tags"), &ProductTag.changeset/2, [
        :icon_key,
        :order
      ])
    end)

    Enum.each(unique_items(entries, "products"), fn item ->
      attrs =
        Map.take(item, Enum.map(Fields.catalog_fields("products"), &Atom.to_string/1))
        |> Map.merge(Map.take(item, ~w(category_id media_id)))

      put_identified(
        Product,
        Map.put(attrs, "id", item["id"]),
        Fields.catalog_fields("products") ++ ~w(category_id media_id)a,
        &Product.changeset/2,
        [:order]
      )
    end)

    Enum.each(unique_items(entries, "modifiers"), fn item ->
      attrs =
        Map.put(item, "photo_key", mapped_key(item["photo_key"], uploaded, plan.public_bucket))

      put_identified(
        Modifier,
        attrs,
        Fields.catalog_fields("modifiers") ++ [:group_id],
        &Modifier.changeset/2,
        [:photo_key]
      )
    end)

    Enum.each(plan.links, &put_link/1)
    put_relations(entries)

    Enum.each(entries, fn entry ->
      Enum.each(entry.data["frontpad_ids"], &put_frontpad_id(entry.target_id, &1))
    end)
  end

  defp put_frontpad_id(branch_id, binding) do
    attrs = %{branch_id: branch_id, provider: "frontpad", external_id: binding["external_id"]}

    changeset =
      %ProductExternalId{entity_type: binding["entity_type"], entity_id: binding["entity_id"]}
      |> ProductExternalId.changeset(attrs)

    case Repo.insert(changeset,
           on_conflict: {:replace, [:branch_id, :external_id, :updated_at]},
           conflict_target: [:entity_type, :entity_id, :provider]
         ) do
      {:ok, _binding} -> :ok
      {:error, changeset} -> abort!({:invalid_record, changeset})
    end
  end

  defp unique_items(entries, type) do
    entries
    |> Enum.flat_map(&(&1.data[type] || []))
    |> Enum.uniq_by(& &1["id"])
  end

  defp put_media(item, uploaded) do
    old = Repo.get(MediaFile, item["id"])
    key = Map.fetch!(uploaded, "#{item["bucket"]}/#{item["key"]}")

    attrs =
      item
      |> Map.take(~w(original_name mime_type size context owner_id is_private))
      |> Map.merge(%{"bucket" => Media.public_bucket(), "key" => key})

    changes = MediaFile.changeset(old || %MediaFile{id: item["id"]}, attrs)

    changes =
      if old && old.key != key,
        do: Ecto.Changeset.put_change(changes, :thumb_key, nil),
        else: changes

    save!(changes)
  end

  defp put_link(item) do
    existing =
      Repo.get_by(ProductModifierGroup,
        product_id: item["product_id"],
        group_id: item["group_id"]
      )

    changes =
      Ecto.Changeset.change(
        existing ||
          %ProductModifierGroup{
            product_id: item["product_id"],
            group_id: item["group_id"]
          },
        position: item["position"]
      )

    save!(changes)
  end

  defp put_relations(entries) do
    Enum.each(entries, fn entry ->
      Enum.each(entry.data["categories"] || [], &relate(entry.target_id, "Category", &1["id"]))
      Enum.each(entry.data["products"] || [], &relate(entry.target_id, "Product", &1["id"]))
    end)
  end

  defp apply_branch_integrations(plan) do
    Enum.each(plan.entries, fn entry ->
      put_branch_integrations(entry.target_id, entry.data["integrations"])
    end)
  end

  defp put_info(branch_id, attrs) do
    current = Repo.get_by(BranchInfo, branch_id: branch_id) || %BranchInfo{branch_id: branch_id}

    safe =
      Map.take(
        attrs,
        Enum.map(Fields.info_fields(), &Atom.to_string/1) ++ ~w(fulfillment kitchen loyalty)
      )

    changes = BranchInfo.changeset(current, safe)
    save!(Ecto.Changeset.put_change(changes, :special_hours, attrs["special_hours"] || %{}))
  end

  defp put_franchise(attrs, uploaded, source_bucket) do
    current = Repo.one(FranchiseSettings) || %FranchiseSettings{}
    fields = Fields.franchise_fields([:franchise])
    safe = Fields.take(attrs, fields)
    public = Map.drop(safe, Enum.map(Fields.image_fields(), &Atom.to_string/1))
    changes = FranchiseSettings.changeset(current, public)

    changes =
      Enum.reduce(Fields.image_fields(), changes, fn field, acc ->
        key = safe[Atom.to_string(field)]
        Ecto.Changeset.put_change(acc, field, mapped_key(key, uploaded, source_bucket))
      end)

    save!(changes)
  end

  defp put_branch_integrations(branch_id, integrations) do
    current = Repo.get_by(BranchInfo, branch_id: branch_id) || %BranchInfo{branch_id: branch_id}

    attrs = Map.reject(integrations || %{}, fn {_key, value} -> is_nil(value) end)
    save!(BranchInfo.changeset(current, attrs))
  end

  defp put_documents(documents) do
    Enum.each(documents || [], fn document ->
      kind = document_kind(document["kind"])
      current = Repo.get_by(LegalDocument, kind: kind) || %LegalDocument{kind: kind}
      save!(LegalDocument.changeset(current, %{kind: kind, body: document["body"]}))
    end)
  end

  defp put_global_integrations(integrations) do
    Enum.each(integrations || %{}, fn {key, attrs} ->
      {module, _fields} = global_integration_schema(key)
      current = Repo.one(module) || struct(module)

      changeset =
        if module == FranchiseSettings,
          do: FranchiseSettings.ratings_changeset(current, attrs),
          else: module.changeset(current, attrs)

      save!(changeset)
    end)
  end

  defp global_integration_schema(key) do
    Enum.find_value(Fields.global_integrations(), fn {name, module, fields} ->
      if name == key, do: {module, fields}
    end) || abort!(:invalid_archive)
  end

  defp put_delivery(branch_id, data) do
    settings = Delivery.get_settings(branch_id)
    attrs = Fields.take(data["delivery_settings"], Fields.settings_fields() ++ [:thresholds])
    put_record(settings, attrs, &Settings.changeset/2)

    Enum.each(data["zones"] || [], fn item ->
      old = Repo.get(Zone, item["id"])
      if old && old.branch_id != branch_id, do: abort!(:zone_conflict)
      zone = old || %Zone{id: item["id"], branch_id: branch_id}

      changes =
        Zone.changeset(zone, Fields.take(item, Fields.zone_fields() ++ [:thresholds]))

      changes =
        changes
        |> Ecto.Changeset.put_change(:polygon, item["polygon"])
        |> Ecto.Changeset.put_change(:radius_km, item["radius_km"])

      save!(changes)
    end)
  end

  defp put_record(record, attrs, fun) do
    record |> fun.(attrs) |> save!()
  end

  defp put_identified(schema, item, fields, fun, extra \\ []) do
    old = Repo.get(schema, item["id"])
    attrs = Fields.take(item, fields)
    changes = fun.(old || struct(schema, id: item["id"]), attrs)

    changes =
      Enum.reduce(extra, changes, fn field, acc ->
        Ecto.Changeset.put_change(acc, field, Map.get(attrs, Atom.to_string(field)))
      end)

    save!(changes)
  end

  defp relate(branch_id, type, id) do
    case Relations.create_relation(Repo, "Branch", branch_id, type, id) do
      {:ok, _} -> :ok
      {:error, reason} -> abort!(reason)
    end
  end

  defp mapped_key(nil, _uploaded, _source_bucket), do: nil

  defp mapped_key(key, uploaded, source_bucket) do
    MediaTransfer.mapped_key(key, uploaded, source_bucket)
  end

  defp document_kind(value) when is_binary(value),
    do: Enum.find(LegalDocument.kinds(), &(to_string(&1) == value))

  defp invalidate_integrations(branch_ids, sections) do
    if :integrations in sections do
      Enum.each(~w(yookassa zvonok dadata yandex_eda)a, &Health.invalidate(&1, nil))

      Enum.each(branch_ids, fn branch_id ->
        Enum.each(~w(crm fiscal channels yandex_delivery)a, &Health.invalidate(&1, branch_id))
      end)
    end
  end

  defp enqueue_thumbnails(ids) do
    ids = ids |> Enum.reject(&is_nil/1) |> Enum.uniq()

    from(file in MediaFile, where: file.id in ^ids)
    |> Repo.all()
    |> Enum.each(&Media.Thumbnails.enqueue/1)
  end

  defp save!(changeset) do
    case Repo.insert_or_update(changeset) do
      {:ok, record} -> record
      {:error, reason} -> abort!(reason)
    end
  end

  defp abort!(reason), do: throw({:snapshot_abort, reason})
end
