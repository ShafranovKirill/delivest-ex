defmodule Delivest.SiteSnapshot do
  @moduledoc """
  Transfers the public configuration of one branch or of the whole franchise
  between identical builds.
  """

  import Ecto.Query
  require Logger

  alias Delivest.{Audit, Delivery, Identity, Media, Relations, Repo}
  alias Delivest.Delivery.{Settings, Zone}
  alias Delivest.Franchise.LegalDocument
  alias Delivest.Franchise.Settings, as: FranchiseSettings
  alias Delivest.Identity.Branch
  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Integrations.{Dadata, Health, YandexEda, Yookassa, Zvonok}
  alias Delivest.Media.File, as: MediaFile
  alias Delivest.SiteSnapshot.{Installation, Mapping}

  alias Delivest.Net.{
    Category,
    Modifier,
    ModifierGroup,
    Product,
    ProductModifierGroup,
    ProductTag
  }

  @max_archive 100 * 1024 * 1024
  @max_file 20 * 1024 * 1024
  @max_files 1000
  @max_branches 100
  @format 1
  @sections [:storefront, :catalog, :franchise, :integrations]
  @source_files Path.wildcard("lib/**/*.ex") ++
                  Path.wildcard("priv/repo/migrations/*.exs") ++ ["mix.lock"]
  @source_files Enum.sort(@source_files)
  for path <- @source_files, do: @external_resource(path)

  @build_id :crypto.hash(:sha256, Enum.map(@source_files, &File.read!/1))
            |> Base.encode16(case: :lower)

  @branch_fields ~w(name is_active)a
  @franchise_branch_fields ~w(name slug code is_active)a
  @info_fields ~w(address city latitude longitude phone_number delivery_time working_hours special_hours vk_url whatsapp_url instagram_url timezone)a
  @franchise_fields ~w(name description primary_color dark_primary_color timezone legal_form legal_name inn ogrn legal_address email phone loyalty_per_rubles loyalty_stars loyalty_expire_days icon_key share_image_key logo_key logo_dark_key)a
  @franchise_integration_fields ~w(yandex_org_id yandex_api_key)a
  @category_fields ~w(name order is_active)a
  @product_fields ~w(name slug old_price price description quantity weight measure_unit calories proteins fats carbohydrates excise vat is_active tags suggested stars_price stars_reward order)a
  @group_fields ~w(name min max position is_active is_size)a
  @modifier_fields ~w(name price max_quantity is_default weight position is_active photo_key)a
  @tag_fields ~w(name icon icon_key order)a
  @zone_fields ~w(name color enabled position polygon radius_km geometry_version delivery_minutes)a
  @settings_fields ~w(mode show_zones outside_zones)a
  @image_fields ~w(icon_key share_image_key logo_key logo_dark_key)a

  def build_id, do: @build_id
  def max_archive, do: @max_archive
  def sections, do: @sections

  def export(staff, branch_id, destination \\ :memory) do
    with :ok <- authorize(staff, branch_id, :read),
         {:ok, data} <- snapshot_data(branch_id),
         {:ok, blobs} <- export_blobs(data),
         {:ok, archive} <- encode_archive(data, blobs, destination, :branch) do
      Audit.record(staff, "site_snapshot.exported", Repo.get!(Branch, branch_id))
      {:ok, archive}
    end
  end

  def import(staff, branch_id, archive) when is_binary(archive) do
    with :ok <- authorize(staff, branch_id, :write),
         {:ok, manifest, data, blobs} <- decode_archive(archive, :branch) do
      result =
        Repo.transaction(
          fn ->
            Repo.query!("SELECT pg_advisory_xact_lock(hashtext($1))", ["site_snapshot_global"])

            try do
              {mapping, counts} = prepare_mapping!(manifest, branch_id, data)
              mapped_data = remap_data(data, mapping)
              preflight!(branch_id, mapped_data, [:storefront, :catalog])

              case upload_blobs(blobs) do
                {:ok, uploaded, keys} ->
                  try do
                    preflight!(branch_id, mapped_data, [:storefront, :catalog])
                    apply_data(branch_id, mapped_data, uploaded)

                    {Map.merge(counts, %{
                       products: length(data["products"]),
                       categories: length(data["categories"]),
                       media: length(data["media"])
                     }), mapping}
                  rescue
                    error ->
                      cleanup(keys)
                      reraise error, __STACKTRACE__
                  catch
                    :throw, {:snapshot_abort, reason} ->
                      cleanup(keys)
                      Repo.rollback(reason)
                  end

                {:error, reason} ->
                  Repo.rollback(reason)
              end
            catch
              :throw, {:snapshot_abort, reason} -> Repo.rollback(reason)
            end
          end,
          timeout: :infinity
        )

      case result do
        {:ok, {counts, mapping}} ->
          Delivest.Net.Catalogs.clear_menu_cache(branch_id)
          Cachex.del(:franchise_cache, :settings)
          Cachex.del(:branch_cache, branch_id)
          media_ids = Enum.map(data["media"], &mapped_id(mapping, "media", &1["id"]))
          enqueue_thumbnails(media_ids)

          Audit.record(staff, "site_snapshot.imported", Repo.get!(Branch, branch_id),
            metadata: counts
          )

          {:ok, counts}

        {:error, reason} ->
          audit_import_failure(staff, branch_id, reason)
          {:error, reason}
      end
    else
      {:error, :forbidden} = error ->
        error

      {:error, reason} = error ->
        audit_import_failure(staff, branch_id, reason)
        error
    end
  end

  def import(_staff, _branch_id, _archive), do: {:error, :invalid_archive}

  def export_franchise(staff, sections, destination \\ :memory) do
    with {:ok, sections} <- normalize_sections(sections),
         :ok <- authorize_franchise(staff, :read),
         {:ok, data} <- franchise_snapshot_data(sections),
         {:ok, blobs} <- export_franchise_blobs(data),
         {:ok, archive} <- encode_archive(data, blobs, destination, :franchise) do
      Audit.record(staff, "site_snapshot.exported", :franchise,
        metadata: %{scope: "franchise", sections: data["sections"]}
      )

      {:ok, archive}
    end
  end

  def import_franchise(staff, archive) when is_binary(archive) do
    with :ok <- authorize_franchise(staff, :write),
         {:ok, manifest, data, blobs} <- decode_archive(archive, :franchise) do
      sections = sections_from_data(data, :franchise)

      result =
        Repo.transaction(
          fn ->
            Repo.query!("SELECT pg_advisory_xact_lock(hashtext($1))", ["site_snapshot_global"])

            try do
              {branches, branch_counts} = prepare_branches!(manifest, data)
              mappings = prepare_franchise_mappings!(manifest, data, branches, sections)

              mapped = remap_franchise_data(data, mappings, sections)

              Enum.each(mapped["branches"], fn branch ->
                target_id = Map.fetch!(branches, branch["branch_id"])
                preflight!(target_id, branch, sections)
              end)

              case upload_blobs(blobs) do
                {:ok, uploaded, keys} ->
                  try do
                    apply_franchise_data(mapped, branches, uploaded, sections)
                    {branch_counts, branches, mappings}
                  rescue
                    error ->
                      cleanup(keys)
                      reraise error, __STACKTRACE__
                  catch
                    :throw, {:snapshot_abort, reason} ->
                      cleanup(keys)
                      Repo.rollback(reason)
                  end

                {:error, reason} ->
                  Repo.rollback(reason)
              end
            catch
              :throw, {:snapshot_abort, reason} -> Repo.rollback(reason)
            end
          end,
          timeout: :infinity
        )

      case result do
        {:ok, {counts, branches, mappings}} ->
          Cachex.clear(:branch_cache)
          Cachex.del(:franchise_cache, :settings)
          invalidate_integrations(branches, sections)
          enqueue_thumbnails(mapped_media_ids(data, mappings, sections))

          counts =
            if :catalog in sections do
              Map.merge(counts, %{
                products: total(data["branches"], "products"),
                categories: total(data["branches"], "categories"),
                media: total(data["branches"], "media")
              })
            else
              counts
            end

          Audit.record(staff, "site_snapshot.imported", :franchise,
            metadata: Map.put(counts, :scope, "franchise")
          )

          {:ok, counts}

        {:error, reason} ->
          audit_franchise_import_failure(staff, reason)
          {:error, reason}
      end
    else
      {:error, :forbidden} = error ->
        error

      {:error, reason} = error ->
        audit_franchise_import_failure(staff, reason)
        error
    end
  end

  def import_franchise(_staff, _archive), do: {:error, :invalid_archive}

  defp audit_import_failure(staff, branch_id, reason) do
    case Repo.get(Branch, branch_id) do
      %Branch{} = branch ->
        Audit.record(staff, "site_snapshot.import_failed", branch,
          metadata: %{reason: inspect(reason)}
        )

      nil ->
        :ok
    end
  end

  defp audit_franchise_import_failure(staff, reason) do
    Audit.record(staff, "site_snapshot.import_failed", :franchise,
      metadata: %{reason: inspect(reason), scope: "franchise"}
    )
  end

  defp authorize(staff, branch_id, mode) do
    permissions =
      case mode do
        :read ->
          ~w(branches.read categories.read products.read delivery.read franchise.update)

        :write ->
          ~w(branches.read branches.update categories.read categories.create categories.update products.read products.create products.update delivery.read delivery.update franchise.update)
      end

    with %Branch{deleted_at: nil} <- Repo.get(Branch, branch_id),
         true <- Enum.all?(permissions, &(Identity.authorize(staff, &1, branch_id) == :ok)) do
      :ok
    else
      _ -> {:error, :forbidden}
    end
  end

  defp authorize_franchise(staff, _mode) do
    if Identity.can?(staff, "admin"), do: :ok, else: {:error, :forbidden}
  end

  defp normalize_sections(sections) when is_list(sections) do
    normalized =
      sections
      |> Enum.map(&section_name/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    if normalized != [] and Enum.all?(sections, &(not is_nil(section_name(&1)))),
      do: {:ok, Enum.filter(@sections, &(&1 in normalized))},
      else: {:error, :invalid_sections}
  end

  defp normalize_sections(_), do: {:error, :invalid_sections}

  defp section_name(section) when is_atom(section),
    do: Enum.find(@sections, &(&1 == section))

  defp section_name(section) when is_binary(section),
    do: Enum.find(@sections, &(Atom.to_string(&1) == section))

  defp section_name(_), do: nil

  defp sections_from_data(_data, :branch), do: [:storefront, :catalog, :franchise]

  defp sections_from_data(data, :franchise) when is_map(data) do
    case data["sections"] do
      list when is_list(list) ->
        Enum.map(list, &section_name/1)

      _ ->
        []
    end
  end

  defp sections_from_data(_data, _scope), do: []

  defp enqueue_thumbnails(ids) do
    ids = ids |> Enum.reject(&is_nil/1) |> Enum.uniq()

    from(file in MediaFile, where: file.id in ^ids)
    |> Repo.all()
    |> Enum.each(&Media.Thumbnails.enqueue/1)
  end

  defp invalidate_integrations(branches, sections) do
    if :integrations in sections do
      Enum.each(~w(yookassa zvonok dadata yandex_eda)a, &Health.invalidate(&1, nil))

      Enum.each(Map.values(branches), fn branch_id ->
        Enum.each(~w(crm fiscal channels yandex_delivery)a, &Health.invalidate(&1, branch_id))
      end)
    end
  end

  defp total(branches, key), do: Enum.reduce(branches, 0, &(length(&1[key] || []) + &2))

  defp snapshot_data(branch_id) do
    Repo.transaction(fn ->
      maybe_repeatable_read!()
      build_snapshot(branch_id, [:storefront, :catalog, :franchise], :branch)
    end)
  end

  defp franchise_snapshot_data(sections) do
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

          franchise_fields =
            if :integrations in sections,
              do: @franchise_fields ++ @franchise_integration_fields,
              else: @franchise_fields

          Map.merge(data, %{
            "franchise" => fields(franchise, franchise_fields),
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

    branch_fields = if mode == :branch, do: @branch_fields, else: @franchise_branch_fields

    data = %{
      "branch_id" => branch_id,
      "branch" => fields(branch, branch_fields)
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
          "info" => info_fields(branch.info),
          "delivery_settings" =>
            Map.put(
              fields(delivery_settings, @settings_fields),
              "thresholds",
              embeds(delivery_settings.thresholds)
            ),
          "zones" =>
            Enum.map(zones, fn z ->
              Map.merge(record(z, @zone_fields), %{"thresholds" => embeds(z.thresholds)})
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
        do: Map.put(data, "integrations", integration_fields(branch.info)),
        else: data

    if mode == :branch do
      franchise = Repo.one(FranchiseSettings) || %FranchiseSettings{}
      Map.put(data, "franchise", fields(franchise, @franchise_fields))
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

    %{
      "categories" => Enum.map(categories, &record(&1, @category_fields)),
      "products" =>
        Enum.map(products, fn p ->
          Map.merge(record(p, @product_fields), %{
            "category_id" => p.category_id,
            "media_id" => p.media_id
          })
        end),
      "groups" => Enum.map(groups, &record(&1, @group_fields)),
      "modifiers" =>
        Enum.map(modifiers, fn m ->
          Map.put(record(m, @modifier_fields), "group_id", m.group_id)
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
      "media" =>
        Enum.map(
          media,
          &record(
            &1,
            ~w(bucket key original_name mime_type size context owner_id is_private)a
          )
        ),
      "tags" => Enum.map(tags, &record(&1, @tag_fields))
    }
  end

  defp custom_documents do
    Repo.all(LegalDocument)
    |> Enum.map(&%{"kind" => to_string(&1.kind), "body" => &1.body})
  end

  defp global_integrations do
    [
      {"yookassa", Yookassa.Settings, Repo.one(Yookassa.Settings),
       ~w(shop_id secret_key webhook_token)a},
      {"zvonok", Zvonok.Settings, Repo.one(Zvonok.Settings),
       ~w(public_key campaign_id webhook_token enabled dev_skip_calls login_call_mode)a},
      {"dadata", Dadata.Settings, Repo.one(Dadata.Settings), ~w(api_key enabled)a},
      {"yandex_eda", YandexEda.Settings, Repo.one(YandexEda.Settings),
       ~w(partner_name push_client_id push_client_secret)a}
    ]
    |> Enum.reject(fn {_key, _module, settings, _fields} -> is_nil(settings) end)
    |> Enum.flat_map(fn {key, module, settings, fields} ->
      attrs = settings |> Map.take(fields) |> Jason.encode!() |> Jason.decode!()

      if module.changeset(struct(module), attrs).valid?,
        do: [{key, attrs}],
        else: []
    end)
    |> Map.new()
  end

  defp fields(nil, _keys), do: %{}

  defp fields(struct, keys),
    do: Map.new(keys, fn key -> {Atom.to_string(key), Map.get(struct, key)} end)

  defp record(struct, keys), do: Map.put(fields(struct, keys), "id", struct.id)
  defp embeds(items), do: Enum.map(items || [], &fields(&1, ~w(order_from price)a))

  defp info_fields(nil), do: %{}

  defp info_fields(info) do
    Map.merge(fields(info, @info_fields), %{
      "fulfillment" => fields(info.fulfillment, ~w(delivery pickup dine_in)a),
      "kitchen" => fields(info.kitchen, ~w(enabled lead_minutes)a),
      "loyalty" => fields(info.loyalty, ~w(shop_enabled enabled spend_enabled max_percent)a)
    })
  end

  defp integration_fields(nil),
    do: Map.new(~w(crm fiscal channels yandex_delivery ycart_settings)a, &{to_string(&1), nil})

  defp integration_fields(info) do
    Map.new(~w(crm fiscal channels yandex_delivery ycart_settings)a, fn field ->
      {Atom.to_string(field), embed_map(Map.get(info, field))}
    end)
  end

  defp embed_map(nil), do: nil
  defp embed_map(struct), do: encode_value(struct)

  defp encode_value(%_{} = struct), do: struct |> Map.from_struct() |> encode_value()

  defp encode_value(map) when is_map(map),
    do: Map.new(map, fn {key, value} -> {to_string(key), encode_value(value)} end)

  defp encode_value(list) when is_list(list), do: Enum.map(list, &encode_value/1)
  defp encode_value(value), do: value

  defp asset_keys(data) do
    franchise = data["franchise"] || %{}
    modifiers = Enum.map(data["modifiers"] || [], & &1["photo_key"])
    tags = Enum.map(data["tags"] || [], & &1["icon_key"])
    expand_asset_keys(franchise, modifiers, tags)
  end

  defp franchise_asset_keys(data) do
    modifiers =
      Enum.flat_map(data["branches"], fn branch ->
        Enum.map(branch["modifiers"] || [], & &1["photo_key"])
      end)

    tags =
      Enum.flat_map(data["branches"], fn branch ->
        Enum.map(branch["tags"] || [], & &1["icon_key"])
      end)

    expand_asset_keys(data["franchise"] || %{}, modifiers, tags)
  end

  defp expand_asset_keys(franchise, modifiers, tags) do
    images =
      Map.take(franchise, Enum.map(@image_fields, &Atom.to_string/1)) |> Map.values()

    Enum.reject(images ++ modifiers ++ tags, &is_nil/1)
    |> Enum.flat_map(fn key ->
      if String.starts_with?(key, "franchise/icon/"),
        do:
          Enum.map(
            ~w(favicon.ico icon-32.png apple-touch-icon.png icon-192.png icon-512.png),
            &"#{key}/#{&1}"
          ),
        else: [key]
    end)
  end

  defp export_blobs(data) do
    files = Enum.map(data["media"], &{&1["bucket"], &1["key"]})
    raw = Enum.map(asset_keys(data), &{Media.public_bucket(), &1})
    refs = Enum.uniq(files ++ raw)

    if Enum.any?(data["media"], &(&1["is_private"] != false)) do
      {:error, :private_media}
    else
      fetch_blobs(refs)
    end
  end

  defp export_franchise_blobs(data) do
    files =
      Enum.flat_map(data["branches"], fn branch ->
        Enum.map(branch["media"] || [], &{&1["bucket"], &1["key"]})
      end)

    raw = Enum.map(franchise_asset_keys(data), &{data["public_bucket"], &1})
    refs = Enum.uniq(files ++ raw)
    private? = Enum.any?(data["branches"], &private_media?/1)

    if private?, do: {:error, :private_media}, else: fetch_blobs(refs)
  end

  defp private_media?(branch),
    do: Enum.any?(branch["media"] || [], &(&1["is_private"] != false))

  defp fetch_blobs(refs) do
    if length(refs) > @max_files do
      {:error, :archive_too_large}
    else
      Enum.reduce_while(refs, {:ok, %{}, 0}, fn {bucket, key}, {:ok, acc, total} ->
        case ExAws.S3.get_object(bucket, key) |> ExAws.request() do
          {:ok, %{body: body}}
          when byte_size(body) <= @max_file and total + byte_size(body) <= @max_archive ->
            if image_type(body) do
              {:cont, {:ok, Map.put(acc, "#{bucket}/#{key}", body), total + byte_size(body)}}
            else
              {:halt, {:error, {:missing_media, bucket, key}}}
            end

          {:ok, _} ->
            {:halt, {:error, :archive_too_large}}

          _ ->
            {:halt, {:error, {:missing_media, bucket, key}}}
        end
      end)
      |> case do
        {:ok, blobs, _total} -> {:ok, blobs}
        error -> error
      end
    end
  end

  defp encode_archive(data, blobs, destination, scope) do
    entries =
      Enum.map(blobs, fn {reference, body} ->
        path = "media/" <> sha(reference)
        {path, body, reference}
      end)

    json = Jason.encode!(data)

    manifest =
      %{
        "format" => @format,
        "scope" => to_string(scope),
        "build" => @build_id,
        "source_installation" => installation_id(),
        "source_branch" => if(scope == :branch, do: data["branch_id"]),
        "data_size" => byte_size(json),
        "data_sha256" => sha(json),
        "files" =>
          Map.new(entries, fn {path, body, ref} ->
            {path, %{"reference" => ref, "size" => byte_size(body), "sha256" => sha(body)}}
          end)
      }
      |> then(fn manifest ->
        if scope == :franchise,
          do: Map.put(manifest, "sections", data["sections"]),
          else: manifest
      end)

    archive_files =
      [{"manifest.json", Jason.encode!(manifest)}, {"data.json", json}] ++
        Enum.map(entries, fn {path, body, _} -> {path, body} end)

    if byte_size(json) > @max_file or
         Enum.reduce(archive_files, 0, fn {_path, body}, sum -> sum + byte_size(body) end) >
           @max_archive do
      {:error, :archive_too_large}
    else
      write_archive(archive_files, destination)
    end
  end

  defp write_archive(files, destination) do
    files = Enum.map(files, fn {path, body} -> {String.to_charlist(path), body} end)

    case destination do
      :memory ->
        case :zip.create(~c"snapshot.zip", files, [:memory, {:uncompress, :all}]) do
          {:ok, {_name, binary}} when byte_size(binary) <= @max_archive -> {:ok, binary}
          {:ok, _} -> {:error, :archive_too_large}
          _ -> {:error, :archive_failed}
        end

      path when is_binary(path) ->
        with {:ok, _} <- :zip.create(String.to_charlist(path), files, [{:uncompress, :all}]),
             {:ok, stat} <- File.stat(path) do
          if stat.size <= @max_archive, do: {:ok, path}, else: {:error, :archive_too_large}
        else
          _ -> {:error, :archive_failed}
        end
    end
  end

  defp sha(data), do: :crypto.hash(:sha256, data) |> Base.encode16(case: :lower)

  defp decode_archive(binary, scope) when byte_size(binary) <= @max_archive do
    with {:ok, entries} <- :zip.list_dir(binary),
         :ok <- validate_entries(entries, binary),
         {:ok, files} <- :zip.extract(binary, [:memory]),
         files = Map.new(files, fn {path, body} -> {List.to_string(path), body} end),
         {:ok, manifest} <- Jason.decode(Map.fetch!(files, "manifest.json")),
         {:ok, data} <- Jason.decode(Map.fetch!(files, "data.json")),
         :ok <- validate_manifest(manifest, files, data, scope),
         sections = sections_from_data(data, scope),
         :ok <- validate_data(data, scope, sections),
         :ok <- validate_references(data, manifest, scope, sections) do
      blobs = Map.new(manifest["files"], fn {path, meta} -> {meta["reference"], files[path]} end)
      {:ok, manifest, data, blobs}
    else
      {:error, :different_build} -> {:error, :different_build}
      _ -> {:error, :invalid_archive}
    end
  rescue
    _ -> {:error, :invalid_archive}
  end

  defp decode_archive(_, _), do: {:error, :archive_too_large}

  defp validate_entries(entries, archive) do
    files = Enum.filter(entries, &(elem(&1, 0) == :zip_file))
    names = Enum.map(files, &List.to_string(elem(&1, 1)))
    total = Enum.reduce(files, 0, fn file, sum -> sum + elem(elem(file, 2), 1) end)

    valid? =
      length(files) <= @max_files + 2 and length(names) == length(Enum.uniq(names)) and
        total <= @max_archive and regular_zip_entries?(archive, length(files)) and
        Enum.all?(files, fn file ->
          name = List.to_string(elem(file, 1))
          info = elem(file, 2)

          elem(info, 2) == :regular and elem(info, 1) <= @max_file and
            elem(file, 5) == elem(info, 1) and stored_entry?(archive, file) and
            (name in ["manifest.json", "data.json"] or
               Regex.match?(~r/^media\/[0-9a-f]{64}$/, name))
        end) and "manifest.json" in names and "data.json" in names

    if valid?, do: :ok, else: {:error, :invalid_archive}
  end

  # OTP's ZIP directory listing reports Unix symlinks as regular files.
  defp regular_zip_entries?(archive, count) when byte_size(archive) >= 22 do
    end_offset = byte_size(archive) - 22

    case binary_part(archive, end_offset, 22) do
      <<0x06054B50::little-32, 0::32, ^count::little-16, ^count::little-16, size::little-32,
        offset::little-32, 0::16>>
      when offset + size == end_offset ->
        archive |> binary_part(offset, size) |> regular_zip_directory?(count)

      _ ->
        false
    end
  end

  defp regular_zip_entries?(_archive, _count), do: false

  defp regular_zip_directory?(<<>>, 0), do: true

  defp regular_zip_directory?(
         <<0x02014B50::little-32, _header::binary-size(24), name_size::little-16,
           extra_size::little-16, comment_size::little-16, 0::16, _internal_attributes::16,
           attributes::little-32, _local_offset::little-32, rest::binary>>,
         count
       )
       when count > 0 and div(attributes, 0x10000000) in [0, 8] do
    skip = name_size + extra_size + comment_size

    case rest do
      <<_::binary-size(skip), tail::binary>> -> regular_zip_directory?(tail, count - 1)
      _ -> false
    end
  end

  defp regular_zip_directory?(_directory, _count), do: false

  defp stored_entry?(archive, file) do
    offset = elem(file, 4)
    name = elem(file, 1) |> List.to_string()

    if is_integer(offset) and offset >= 0 and offset + 30 <= byte_size(archive) do
      <<_skip::binary-size(offset), header::binary-size(30), _rest::binary>> = archive

      case header do
        <<0x04034B50::little-32, _version::little-16, 0::little-16, 0::little-16,
          _time::little-16, _date::little-16, _crc::little-32, compressed::little-32,
          uncompressed::little-32, name_size::little-16, extra_size::little-16>> ->
          body_offset = offset + 30 + name_size + extra_size

          body_offset + uncompressed <= byte_size(archive) and
            uncompressed == elem(elem(file, 2), 1) and compressed == uncompressed and
            name_size == byte_size(name) and
            binary_part(archive, offset + 30, name_size) == name

        _ ->
          false
      end
    else
      false
    end
  end

  defp validate_manifest(
         %{"format" => @format, "build" => @build_id, "files" => meta} = manifest,
         files,
         data,
         :branch
       )
       when is_map(meta) do
    names = Map.keys(files) |> MapSet.new()
    expected = ["manifest.json", "data.json" | Map.keys(meta)] |> MapSet.new()
    scope = manifest["scope"] || "branch"

    valid? =
      names == expected and scope == "branch" and
        Ecto.UUID.cast(manifest["source_installation"]) != :error and
        Ecto.UUID.cast(manifest["source_branch"]) != :error and
        manifest["source_branch"] == data["branch_id"] and
        manifest["data_size"] == byte_size(files["data.json"]) and
        manifest["data_sha256"] == sha(files["data.json"]) and
        valid_file_meta?(files, meta)

    if valid?, do: :ok, else: {:error, :invalid_archive}
  end

  defp validate_manifest(
         %{
           "format" => @format,
           "build" => @build_id,
           "scope" => "franchise",
           "files" => meta
         } = manifest,
         files,
         data,
         :franchise
       )
       when is_map(meta) do
    names = Map.keys(files) |> MapSet.new()
    expected = ["manifest.json", "data.json" | Map.keys(meta)] |> MapSet.new()

    valid? =
      names == expected and
        Ecto.UUID.cast(manifest["source_installation"]) != :error and
        is_nil(manifest["source_branch"]) and
        manifest["sections"] == data["sections"] and
        manifest["data_size"] == byte_size(files["data.json"]) and
        manifest["data_sha256"] == sha(files["data.json"]) and
        valid_file_meta?(files, meta)

    if valid?, do: :ok, else: {:error, :invalid_archive}
  end

  defp validate_manifest(%{"build" => build}, _files, _data, _scope) when build != @build_id,
    do: {:error, :different_build}

  defp validate_manifest(_, _, _, _), do: {:error, :invalid_archive}

  defp valid_file_meta?(files, meta) do
    Enum.all?(meta, fn {path, info} ->
      body = files[path]

      is_binary(body) and image_type(body) != nil and is_map(info) and
        is_binary(info["reference"]) and
        String.starts_with?(path, "media/") and info["size"] == byte_size(body) and
        info["sha256"] == sha(body) and path == "media/" <> sha(info["reference"])
    end)
  end

  defp validate_data(data, :branch, _sections) when is_map(data) do
    collections = ~w(categories products groups modifiers links media tags zones)
    maps = ~w(branch info franchise delivery_settings)

    if is_binary(data["public_bucket"]) and Ecto.UUID.cast(data["branch_id"]) != :error and
         Enum.all?(collections, fn key ->
           is_list(data[key]) and length(data[key]) <= 10_000 and Enum.all?(data[key], &is_map/1)
         end) and
         Enum.all?(maps, &is_map(data[&1])) and
         valid_fields?(data) and valid_changesets?(data) and valid_links?(data) and
         Enum.all?(
           ~w(categories products groups modifiers media tags zones),
           &unique_ids?(data[&1])
         ) and
         references_valid?(data) do
      :ok
    else
      {:error, :invalid_archive}
    end
  end

  defp validate_data(data, :franchise, sections)
       when is_map(data) and is_list(sections) and sections != [] do
    branch_entries = data["branches"]

    if is_binary(data["public_bucket"]) and is_list(data["sections"]) and
         data["sections"] == Enum.map(sections, &Atom.to_string/1) and
         is_list(branch_entries) and length(branch_entries) in 1..@max_branches and
         Enum.all?(branch_entries, &valid_franchise_branch?(&1, sections)) and
         unique_branch_ids?(branch_entries) and
         franchise_part_valid?(data, :franchise in sections, :integrations in sections) and
         integration_part_valid?(data, :integrations in sections) do
      :ok
    else
      {:error, :invalid_archive}
    end
  end

  defp validate_data(_data, _scope, _sections), do: {:error, :invalid_archive}

  defp unique_branch_ids?(branches) do
    ids = Enum.map(branches, & &1["branch_id"])
    Enum.all?(ids, &(Ecto.UUID.cast(&1) != :error)) and length(ids) == length(Enum.uniq(ids))
  end

  defp valid_franchise_branch?(branch, sections) when is_map(branch) do
    storefront? = :storefront in sections
    catalog? = :catalog in sections
    integrations? = :integrations in sections

    keys =
      ["branch_id", "branch"] ++
        if(storefront?, do: ~w(info delivery_settings zones), else: []) ++
        if(catalog?, do: ~w(categories products groups modifiers links media tags), else: []) ++
        if(integrations?, do: ["integrations"], else: [])

    branch_fields = Enum.map(@franchise_branch_fields, &Atom.to_string/1)
    branch_attrs = branch["branch"]

    MapSet.new(Map.keys(branch)) == MapSet.new(keys) and
      Ecto.UUID.cast(branch["branch_id"]) != :error and
      is_map(branch_attrs) and
      MapSet.new(Map.keys(branch_attrs)) == MapSet.new(branch_fields) and
      Branch.changeset(%Branch{}, branch_attrs).valid? and
      (not storefront? or valid_storefront?(branch)) and
      (not catalog? or valid_catalog?(branch)) and
      (not integrations? or
         valid_branch_integrations?(branch["integrations"], branch["branch_id"]))
  end

  defp valid_franchise_branch?(_branch, _sections), do: false

  defp valid_storefront?(branch) do
    settings = branch["delivery_settings"]
    zones = branch["zones"]

    is_map(settings) and
      valid_record_keys?(settings, @settings_fields ++ [:thresholds]) and
      threshold_fields?(settings["thresholds"]) and
      Settings.changeset(
        %Settings{},
        Map.take(settings, Enum.map(@settings_fields, &Atom.to_string/1))
      )
      |> Map.get(:valid?) and
      is_list(zones) and length(zones) <= 10_000 and unique_ids?(zones) and
      Enum.all?(zones, &valid_zone?/1) and
      valid_branch_info?(branch["info"], branch["branch_id"])
  end

  defp valid_zone?(zone) when is_map(zone) do
    valid_record_keys?(zone, @zone_fields ++ ["id", "thresholds"]) and
      threshold_fields?(zone["thresholds"]) and
      Zone.changeset(
        %Zone{},
        Map.take(zone, Enum.map(@zone_fields, &Atom.to_string/1) ++ ["thresholds"])
      ).valid?
  end

  defp valid_zone?(_zone), do: false

  defp valid_branch_info?(%{} = info, _branch_id) when map_size(info) == 0, do: true
  defp valid_branch_info?(info, branch_id), do: valid_info?(info, branch_id)

  defp valid_info?(info, branch_id) when is_map(info) do
    allowed = Enum.map(@info_fields, &Atom.to_string/1) ++ ~w(fulfillment kitchen loyalty)

    MapSet.new(Map.keys(info)) == MapSet.new(allowed) and
      nested_fields?(info, "fulfillment", ~w(delivery pickup dine_in)) and
      nested_fields?(info, "kitchen", ~w(enabled lead_minutes)) and
      nested_fields?(info, "loyalty", ~w(shop_enabled enabled spend_enabled max_percent)) and
      BranchInfo.changeset(%BranchInfo{branch_id: branch_id}, info).valid?
  end

  defp valid_info?(_info, _branch_id), do: false

  defp valid_record_keys?(record, keys) when is_map(record) do
    MapSet.new(Map.keys(record)) ==
      MapSet.new(Enum.map(keys, &(&1 |> to_string())))
  end

  defp valid_record_keys?(_record, _keys), do: false

  defp valid_catalog?(branch) do
    collections = ~w(categories products groups modifiers links media tags)

    Enum.all?(collections, fn key ->
      is_list(branch[key]) and length(branch[key]) <= 10_000 and
        Enum.all?(branch[key], &is_map/1)
    end) and
      Enum.all?(~w(categories products groups modifiers media tags), &unique_ids?(branch[&1])) and
      valid_links?(branch) and references_valid?(branch) and valid_catalog_changesets?(branch) and
      Enum.all?(branch["products"], fn product ->
        Map.has_key?(product, "category_id") and Map.has_key?(product, "media_id") and
          is_list(product["tags"])
      end) and
      Enum.all?(branch["media"], &Map.has_key?(&1, "owner_id"))
  end

  defp valid_branch_integrations?(integrations, branch_id) when is_map(integrations) do
    allowed = ~w(crm fiscal channels yandex_delivery ycart_settings)

    MapSet.new(Map.keys(integrations)) == MapSet.new(allowed) and
      Enum.all?(integrations, fn {_key, value} -> is_nil(value) or is_map(value) end) and
      integrations
      |> Map.reject(fn {_key, value} -> is_nil(value) end)
      |> then(&BranchInfo.changeset(%BranchInfo{branch_id: branch_id}, &1))
      |> Map.get(:valid?)
  end

  defp valid_branch_integrations?(_integrations, _branch_id), do: false

  defp franchise_part_valid?(data, false, _integrations?) do
    not Map.has_key?(data, "franchise") and not Map.has_key?(data, "documents")
  end

  defp franchise_part_valid?(data, true, integrations?) do
    fields = Enum.map(@franchise_fields, &Atom.to_string/1)

    fields =
      if integrations?,
        do: fields ++ Enum.map(@franchise_integration_fields, &Atom.to_string/1),
        else: fields

    franchise = data["franchise"]

    is_map(franchise) and MapSet.new(Map.keys(franchise)) == MapSet.new(fields) and
      FranchiseSettings.changeset(%FranchiseSettings{}, franchise).valid? and
      valid_documents?(data["documents"])
  end

  defp valid_documents?(documents) when is_list(documents) and length(documents) <= 20 do
    kinds = Enum.map(documents, & &1["kind"])

    Enum.all?(documents, fn document ->
      is_map(document) and
        MapSet.new(Map.keys(document)) == MapSet.new(~w(kind body)) and
        document_kind(document["kind"]) != nil and
        is_binary(document["body"]) and byte_size(document["body"]) <= 100_000 and
        LegalDocument.changeset(%LegalDocument{}, %{
          kind: document_kind(document["kind"]),
          body: document["body"]
        }).valid?
    end) and length(kinds) == length(Enum.uniq(kinds))
  end

  defp valid_documents?(_documents), do: false

  defp document_kind(value) when is_binary(value),
    do: Enum.find(LegalDocument.kinds(), &(to_string(&1) == value))

  defp document_kind(_value), do: nil

  defp integration_part_valid?(data, false), do: not Map.has_key?(data, "integrations")

  defp integration_part_valid?(data, true) do
    integrations = data["integrations"]

    is_map(integrations) and
      MapSet.subset?(
        MapSet.new(Map.keys(integrations)),
        MapSet.new(~w(yookassa zvonok dadata yandex_eda))
      ) and
      Enum.all?(integrations, &valid_global_integration?/1)
  end

  defp valid_global_integration?({key, attrs}) when is_map(attrs) do
    case global_integration_schema(key) do
      {module, fields} ->
        MapSet.new(Map.keys(attrs)) == MapSet.new(fields) and
          module.changeset(struct(module), attrs).valid?

      nil ->
        false
    end
  end

  defp valid_global_integration?(_entry), do: false

  defp global_integration_schema("yookassa"),
    do: {Yookassa.Settings, ~w(shop_id secret_key webhook_token)}

  defp global_integration_schema("zvonok"),
    do:
      {Zvonok.Settings,
       ~w(public_key campaign_id webhook_token enabled dev_skip_calls login_call_mode)}

  defp global_integration_schema("dadata"), do: {Dadata.Settings, ~w(api_key enabled)}

  defp global_integration_schema("yandex_eda"),
    do: {YandexEda.Settings, ~w(partner_name push_client_id push_client_secret)}

  defp global_integration_schema(_key), do: nil

  defp unique_ids?(records) do
    ids = Enum.map(records, & &1["id"])

    Enum.all?(ids, &(Ecto.UUID.cast(&1) != :error)) and length(ids) == length(Enum.uniq(ids))
  end

  defp valid_fields?(data) do
    allowed = %{
      "branch" => Enum.map(@branch_fields, &Atom.to_string/1),
      "info" => Enum.map(@info_fields, &Atom.to_string/1) ++ ~w(fulfillment kitchen loyalty),
      "franchise" => Enum.map(@franchise_fields, &Atom.to_string/1),
      "delivery_settings" => Enum.map(@settings_fields, &Atom.to_string/1) ++ ["thresholds"],
      "categories" => Enum.map(@category_fields, &Atom.to_string/1) ++ ["id"],
      "products" => Enum.map(@product_fields, &Atom.to_string/1) ++ ~w(id category_id media_id),
      "groups" => Enum.map(@group_fields, &Atom.to_string/1) ++ ["id"],
      "modifiers" => Enum.map(@modifier_fields, &Atom.to_string/1) ++ ~w(id group_id),
      "links" => ~w(product_id group_id position),
      "media" => ~w(id bucket key original_name mime_type size context owner_id is_private),
      "tags" => Enum.map(@tag_fields, &Atom.to_string/1) ++ ["id"],
      "zones" => Enum.map(@zone_fields, &Atom.to_string/1) ++ ~w(id thresholds)
    }

    MapSet.new(Map.keys(data)) == MapSet.new(Map.keys(allowed) ++ ~w(public_bucket branch_id)) and
      Enum.all?(allowed, fn {key, fields} ->
        records = if is_list(data[key]), do: data[key], else: [data[key]]

        Enum.all?(records, fn record ->
          keys = Map.keys(record)
          key_set = MapSet.new(keys)
          allowed_set = MapSet.new(fields)
          key_set == allowed_set or (key == "info" and keys == [])
        end)
      end) and
      nested_fields?(data["info"], "fulfillment", ~w(delivery pickup dine_in)) and
      nested_fields?(data["info"], "kitchen", ~w(enabled lead_minutes)) and
      nested_fields?(data["info"], "loyalty", ~w(shop_enabled enabled spend_enabled max_percent)) and
      threshold_fields?(data["delivery_settings"]["thresholds"]) and
      Enum.all?(data["zones"], &threshold_fields?(&1["thresholds"])) and
      Enum.all?(data["products"], fn product ->
        Map.has_key?(product, "category_id") and Map.has_key?(product, "media_id") and
          is_list(product["tags"])
      end) and
      Enum.all?(data["media"], &Map.has_key?(&1, "owner_id"))
  end

  defp references_valid?(data) do
    categories = MapSet.new(Enum.map(data["categories"], & &1["id"]))
    products = MapSet.new(Enum.map(data["products"], & &1["id"]))
    groups = MapSet.new(Enum.map(data["groups"], & &1["id"]))
    media = MapSet.new(Enum.map(data["media"], & &1["id"]))
    tags = MapSet.new(Enum.map(data["tags"], & &1["id"]))

    Enum.all?(data["products"], fn product ->
      (is_nil(product["category_id"]) or MapSet.member?(categories, product["category_id"])) and
        (is_nil(product["media_id"]) or MapSet.member?(media, product["media_id"])) and
        Enum.all?(product["tags"], &MapSet.member?(tags, &1))
    end) and
      Enum.all?(data["modifiers"], &MapSet.member?(groups, &1["group_id"])) and
      Enum.all?(data["links"], fn link ->
        MapSet.member?(products, link["product_id"]) and
          MapSet.member?(groups, link["group_id"])
      end)
  end

  defp valid_links?(data) do
    links = Enum.map(data["links"], &{&1["product_id"], &1["group_id"]})
    length(links) == MapSet.size(MapSet.new(links))
  end

  defp valid_changesets?(data) do
    valid_catalog_changesets?(data) and
      FranchiseSettings.changeset(%FranchiseSettings{}, data["franchise"]).valid? and
      Settings.changeset(%Settings{}, data["delivery_settings"]).valid? and
      (data["info"] == %{} or
         BranchInfo.changeset(%BranchInfo{branch_id: data["branch_id"]}, data["info"]).valid?)
  end

  defp valid_catalog_changesets?(data) do
    records = [
      {"categories", Category},
      {"products", Product},
      {"groups", ModifierGroup},
      {"modifiers", Modifier},
      {"media", MediaFile},
      {"tags", ProductTag},
      {"zones", Zone}
    ]

    Enum.all?(records, fn {type, schema} ->
      Enum.all?(data[type] || [], fn item ->
        schema.changeset(struct(schema), item).valid?
      end)
    end)
  end

  defp nested_fields?(parent, key, allowed) do
    case parent[key] do
      value when is_map(value) -> Map.keys(value) -- allowed == []
      nil -> true
      _ -> false
    end
  end

  defp threshold_fields?(items) when is_list(items),
    do: Enum.all?(items, &(is_map(&1) and Map.keys(&1) -- ~w(order_from price) == []))

  defp threshold_fields?(_), do: false

  defp validate_references(data, manifest, :branch, _sections) do
    public_bucket = data["public_bucket"]
    media_refs = Enum.map(data["media"], &"#{&1["bucket"]}/#{&1["key"]}")
    asset_refs = Enum.map(asset_keys(data), &"#{public_bucket}/#{&1}")
    expected = MapSet.new(media_refs ++ asset_refs)
    actual = manifest["files"] |> Map.values() |> Enum.map(& &1["reference"]) |> MapSet.new()

    if expected == actual and Enum.all?(data["media"], &(&1["is_private"] == false)),
      do: :ok,
      else: {:error, :invalid_archive}
  end

  defp validate_references(data, manifest, :franchise, sections) do
    public_bucket = data["public_bucket"]

    media_refs =
      if :catalog in sections do
        Enum.flat_map(data["branches"], fn branch ->
          Enum.map(branch["media"], &"#{&1["bucket"]}/#{&1["key"]}")
        end)
      else
        []
      end

    asset_refs =
      if :franchise in sections do
        Enum.map(franchise_asset_keys(data), &"#{public_bucket}/#{&1}")
      else
        []
      end

    expected = MapSet.new(media_refs ++ asset_refs)
    actual = manifest["files"] |> Map.values() |> Enum.map(& &1["reference"]) |> MapSet.new()
    private? = Enum.any?(data["branches"], &private_media?/1)

    if expected == actual and not private?, do: :ok, else: {:error, :invalid_archive}
  end

  defp validate_references(_data, _manifest, _scope, _sections),
    do: {:error, :invalid_archive}

  defp upload_blobs(blobs) do
    Enum.reduce_while(blobs, {:ok, %{}, []}, fn {reference, body}, {:ok, mapping, keys} ->
      key = storage_key(reference, body)
      bucket = Media.public_bucket()

      result =
        case ExAws.S3.get_object(bucket, key) |> ExAws.request() do
          {:ok, %{body: existing}} when existing == body ->
            :existing

          {:ok, _} ->
            {:error, :media_conflict}

          {:error, {:http_error, 404, _}} ->
            ExAws.S3.put_object(bucket, key, body, content_type: image_type(body))
            |> ExAws.request()

          error ->
            error
        end

      mapping = Map.put(mapping, reference, key)

      mapping =
        case icon_directory(reference, key) do
          {source_dir, target_dir} -> Map.put(mapping, source_dir, target_dir)
          nil -> mapping
        end

      case result do
        :existing ->
          {:cont, {:ok, mapping, keys}}

        {:ok, _} ->
          {:cont, {:ok, mapping, [key | keys]}}

        _ ->
          cleanup(keys)
          {:halt, {:error, :media_upload_failed}}
      end
    end)
    |> case do
      {:ok, mapping, keys} -> {:ok, mapping, keys}
      error -> error
    end
  end

  defp image_type(<<137, "PNG", 13, 10, 26, 10, _::binary>>), do: "image/png"
  defp image_type(<<255, 216, 255, _::binary>>), do: "image/jpeg"
  defp image_type(<<"RIFF", _::32, "WEBP", _::binary>>), do: "image/webp"
  defp image_type(<<0, 0, 1, 0, _::binary>>), do: "image/x-icon"
  defp image_type(_), do: nil

  defp storage_key(reference, body) do
    case Regex.run(
           ~r{/franchise/icon/[^/]+/(favicon\.ico|icon-32\.png|apple-touch-icon\.png|icon-192\.png|icon-512\.png)$},
           reference
         ) do
      [_, filename] -> "franchise/icon/snapshot-#{sha(Path.dirname(reference))}/#{filename}"
      _ -> "site-snapshot/#{sha(reference)}/#{sha(body)}"
    end
  end

  defp icon_directory(reference, key) do
    if String.contains?(reference, "/franchise/icon/") do
      {Path.dirname(reference), Path.dirname(key)}
    end
  end

  defp cleanup(keys) do
    Enum.each(keys, fn key ->
      case ExAws.S3.delete_object(Media.public_bucket(), key) |> ExAws.request() do
        {:ok, _} -> :ok
        _ -> Logger.warning("Site snapshot could not clean up uploaded image #{key}")
      end
    end)
  end

  defp installation_id do
    Repo.insert(%Installation{id: 1, installation_id: Ecto.UUID.generate()},
      on_conflict: :nothing,
      conflict_target: :id
    )

    Repo.get!(Installation, 1).installation_id
  end

  defp prepare_branches!(manifest, data) do
    source = manifest["source_installation"]

    Enum.reduce(
      data["branches"],
      {%{}, %{branches_created: 0, branches_updated: 0}},
      fn entry, {branches, counts} ->
        source_id = entry["branch_id"]
        attrs = entry["branch"]

        {branch, created?} =
          case find_target_branch(source, source_id, attrs["slug"]) do
            nil -> {put_branch!(%Branch{}, attrs), true}
            %Branch{} = branch -> {branch, false}
          end

        put_branch_mapping!(source, branch.id, source_id)

        state = if created?, do: :branches_created, else: :branches_updated
        {Map.put(branches, source_id, branch.id), Map.update!(counts, state, &(&1 + 1))}
      end
    )
  end

  defp find_target_branch(source, source_id, slug) do
    mapped =
      Repo.get_by(Mapping,
        source_installation_id: source,
        entity_type: "branches",
        source_id: source_id
      )

    cond do
      mapped -> Repo.get(Branch, mapped.target_id)
      is_binary(slug) -> Repo.get_by(Branch, slug: slug)
      true -> nil
    end
  end

  defp put_branch_mapping!(source, target_id, source_id) do
    existing =
      Repo.get_by(Mapping,
        target_branch_id: target_id,
        entity_type: "branches",
        target_id: target_id
      )

    if existing do
      if existing.source_id != source_id or existing.source_installation_id != source do
        existing
        |> Ecto.Changeset.change(
          source_id: source_id,
          source_installation_id: source
        )
        |> Repo.update!()
      end
    else
      Repo.insert!(%Mapping{
        source_installation_id: source,
        target_branch_id: target_id,
        entity_type: "branches",
        source_id: source_id,
        target_id: target_id
      })
    end
  end

  defp put_branch!(branch, attrs) do
    validate_branch_conflicts!(attrs, branch)
    code = resolve_code(attrs["code"], attrs["slug"], branch)

    changes =
      branch
      |> Branch.changeset(Map.put(attrs, "code", code))
      |> Ecto.Changeset.put_change(:deleted_at, nil)

    save!(changes)
  end

  defp validate_branch_conflicts!(attrs, branch) do
    slug = attrs["slug"]
    slug_match = if is_binary(slug), do: Repo.get_by(Branch, slug: slug)

    if slug_match && slug_match.id != branch.id, do: abort!({:branch_conflict, :slug})

    name = attrs["name"]
    name_match = if is_binary(name), do: Repo.get_by(Branch, name: name)

    if name_match && name_match.id != branch.id, do: abort!({:branch_conflict, :name})
  end

  defp resolve_code(code, slug, branch) do
    preferred =
      case normalize_code(code) do
        value when is_binary(value) and byte_size(value) >= 2 -> value
        _ -> slug |> Branch.code_from() |> pad_code()
      end

    cond do
      branch.id && branch.code == preferred ->
        preferred

      branch.id && is_binary(branch.code) ->
        branch.code

      true ->
        free_branch_code(preferred, branch.id)
    end
  end

  defp normalize_code(code) when is_binary(code) do
    code
    |> String.upcase()
    |> String.replace(~r/[^A-Z0-9]/, "")
    |> String.slice(0, 6)
  end

  defp normalize_code(_code), do: nil

  defp pad_code(code) when byte_size(code) >= 2, do: code
  defp pad_code(_code), do: "BR"

  defp free_branch_code(base, branch_id) do
    base = String.slice(base, 0, 6)

    candidates =
      [base] ++
        Enum.map(1..99, fn number ->
          suffix = Integer.to_string(number)
          String.slice(base, 0, 6 - String.length(suffix)) <> suffix
        end)

    Enum.find(candidates, fn candidate ->
      String.length(candidate) in 2..6 and
        case Repo.get_by(Branch, code: candidate) do
          nil -> true
          %Branch{id: id} -> id == branch_id
        end
    end) || abort!(:branch_code_conflict)
  end

  defp prepare_franchise_mappings!(manifest, data, branches, sections) do
    types =
      if :catalog in sections, do: catalog_mapping_types(), else: []

    types =
      if :storefront in sections, do: types ++ [{"zones", Zone}], else: types

    Map.new(data["branches"], fn entry ->
      source_id = entry["branch_id"]
      target_id = Map.fetch!(branches, source_id)
      {mapping, _counts} = prepare_mapping!(manifest, target_id, entry, types)
      {source_id, mapping}
    end)
  end

  defp catalog_mapping_types do
    [
      {"categories", Category},
      {"groups", ModifierGroup},
      {"media", MediaFile},
      {"tags", ProductTag},
      {"products", Product},
      {"modifiers", Modifier}
    ]
  end

  defp prepare_mapping!(manifest, branch_id, data, types \\ nil) do
    source = manifest["source_installation"]
    types = types || catalog_mapping_types() ++ [{"zones", Zone}]

    Enum.reduce(types, {%{}, %{created: 0, updated: 0}}, fn {type, schema}, {mapping, counts} ->
      Enum.reduce(data[type] || [], {mapping, counts}, fn item, {ids, tally} ->
        source_id = item["id"]

        existing =
          Repo.get_by(Mapping,
            source_installation_id: source,
            target_branch_id: branch_id,
            entity_type: type,
            source_id: source_id
          )

        target_id =
          if existing do
            existing.target_id
          else
            candidate_id(type, schema, item, branch_id)
          end

        if is_nil(existing) do
          if Repo.get_by(Mapping,
               target_branch_id: branch_id,
               entity_type: type,
               target_id: target_id
             ),
             do: abort!(:ambiguous_match)

          Repo.insert!(%Mapping{
            source_installation_id: source,
            target_branch_id: branch_id,
            entity_type: type,
            source_id: source_id,
            target_id: target_id
          })
        end

        state = if Repo.get(schema, target_id), do: :updated, else: :created
        {Map.put(ids, {type, source_id}, target_id), Map.update!(tally, state, &(&1 + 1))}
      end)
    end)
  end

  defp candidate_id("products", Product, item, branch_id) do
    slug_match = if is_binary(item["slug"]), do: Repo.get_by(Product, slug: item["slug"])

    cond do
      slug_match && Relations.related?("Branch", branch_id, "Product", slug_match.id) ->
        slug_match.id

      slug_match ->
        abort!({:shared_catalog_conflict, "Product", slug_match.id})

      true ->
        candidate_id_for_source(Product, item["id"], branch_id, "products")
    end
  end

  defp candidate_id(type, schema, item, branch_id) do
    candidate_id_for_source(schema, item["id"], branch_id, type)
  end

  defp candidate_id_for_source(schema, source_id, branch_id, type) do
    case Repo.get(schema, source_id) do
      nil ->
        source_id

      %Zone{branch_id: ^branch_id} ->
        source_id

      %Zone{} ->
        Ecto.UUID.generate()

      _ when type in ["categories", "products"] ->
        relation_type = if type == "categories", do: "Category", else: "Product"

        if Relations.related?("Branch", branch_id, relation_type, source_id),
          do: source_id,
          else: Ecto.UUID.generate()

      _ ->
        Ecto.UUID.generate()
    end
  end

  defp mapped_id(mapping, type, source_id) when is_binary(source_id),
    do: Map.fetch!(mapping, {type, source_id})

  defp mapped_id(_mapping, _type, nil), do: nil

  defp remap_data(data, mapping) do
    data
    |> remap_catalog_data(mapping)
    |> remap_zones(mapping)
  end

  defp remap_franchise_data(data, mappings, sections) do
    Map.update!(data, "branches", fn branches ->
      Enum.map(branches, fn branch ->
        mapping = Map.fetch!(mappings, branch["branch_id"])

        branch
        |> then(fn value ->
          if :catalog in sections, do: remap_catalog_data(value, mapping), else: value
        end)
        |> then(fn value ->
          if :storefront in sections, do: remap_zones(value, mapping), else: value
        end)
      end)
    end)
  end

  defp remap_catalog_data(data, mapping) do
    update = fn type, fun ->
      Enum.map(data[type] || [], fn item ->
        item |> Map.put("id", mapped_id(mapping, type, item["id"])) |> fun.()
      end)
    end

    data
    |> Map.put("categories", update.("categories", & &1))
    |> Map.put("groups", update.("groups", & &1))
    |> Map.put(
      "media",
      update.("media", fn item ->
        Map.update!(item, "owner_id", fn owner -> Map.get(mapping, {"products", owner}, owner) end)
      end)
    )
    |> Map.put("tags", update.("tags", & &1))
    |> Map.put(
      "products",
      update.("products", fn item ->
        item
        |> Map.update!("category_id", &mapped_id(mapping, "categories", &1))
        |> Map.update!("media_id", &mapped_id(mapping, "media", &1))
        |> Map.update!("tags", fn tags ->
          Enum.map(tags || [], &mapped_id(mapping, "tags", &1))
        end)
      end)
    )
    |> Map.put(
      "modifiers",
      update.("modifiers", fn item ->
        Map.update!(item, "group_id", &mapped_id(mapping, "groups", &1))
      end)
    )
    |> Map.put(
      "links",
      Enum.map(data["links"] || [], fn item ->
        item
        |> Map.update!("product_id", &mapped_id(mapping, "products", &1))
        |> Map.update!("group_id", &mapped_id(mapping, "groups", &1))
      end)
    )
  end

  defp remap_zones(data, mapping) do
    Map.update(data, "zones", [], fn zones ->
      Enum.map(zones, fn item ->
        Map.update!(item, "id", &mapped_id(mapping, "zones", &1))
      end)
    end)
  end

  defp mapped_media_ids(data, mappings, sections) do
    if :catalog in sections do
      Enum.flat_map(data["branches"], fn branch ->
        mapping = Map.fetch!(mappings, branch["branch_id"])
        Enum.map(branch["media"] || [], &mapped_id(mapping, "media", &1["id"]))
      end)
    else
      []
    end
  end

  defp preflight!(branch_id, data, sections) do
    if :catalog in sections do
      Enum.each(data["categories"], &assert_unshared!("Category", &1["id"], branch_id))
      Enum.each(data["groups"], &assert_group_unshared!(&1["id"], branch_id))
      Enum.each(data["tags"], &assert_tag_unshared!(&1["id"], branch_id))
      Enum.each(data["products"], &assert_unshared!("Product", &1["id"], branch_id))
      Enum.each(data["modifiers"], &assert_modifier_owned!(&1["id"], &1["group_id"], branch_id))
    end

    if :storefront in sections do
      Enum.each(data["zones"] || [], fn zone ->
        case Repo.get(Zone, zone["id"]) do
          %Zone{branch_id: ^branch_id} -> :ok
          nil -> :ok
          _ -> abort!(:zone_conflict)
        end
      end)
    end
  end

  defp apply_data(branch_id, data, uploaded) do
    branch = Repo.get!(Branch, branch_id)
    put_record(branch, data["branch"], &Branch.changeset/2)
    put_info(branch_id, data["info"])
    put_franchise(data["franchise"], uploaded, data["public_bucket"])
    put_delivery(branch_id, data)
    apply_catalog(branch_id, data, uploaded, data["public_bucket"])

    %{
      products: length(data["products"]),
      categories: length(data["categories"]),
      media: length(data["media"])
    }
  end

  defp apply_catalog(branch_id, data, uploaded, source_bucket) do
    Enum.each(data["categories"], fn item ->
      assert_unshared!("Category", item["id"], branch_id)
      put_identified(Category, item, @category_fields, &Category.changeset/2)
      relate(branch_id, "Category", item["id"])
    end)

    Enum.each(data["groups"], fn item ->
      assert_group_unshared!(item["id"], branch_id)
      put_identified(ModifierGroup, item, @group_fields, &ModifierGroup.changeset/2)
    end)

    Enum.each(data["media"], fn item ->
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
    end)

    Enum.each(data["tags"], fn item ->
      assert_tag_unshared!(item["id"], branch_id)

      attrs =
        Map.put(item, "icon_key", mapped_key(item["icon_key"], uploaded, source_bucket))

      put_identified(ProductTag, attrs, @tag_fields, &ProductTag.changeset/2, [:icon_key, :order])
    end)

    Enum.each(data["products"], fn item ->
      assert_unshared!("Product", item["id"], branch_id)

      attrs =
        Map.take(item, Enum.map(@product_fields, &Atom.to_string/1))
        |> Map.merge(Map.take(item, ~w(category_id media_id)))

      put_identified(
        Product,
        Map.put(attrs, "id", item["id"]),
        @product_fields ++ ~w(category_id media_id)a,
        &Product.changeset/2,
        [:order]
      )

      relate(branch_id, "Product", item["id"])
    end)

    Enum.each(data["modifiers"], fn item ->
      assert_modifier_owned!(item["id"], item["group_id"], branch_id)

      attrs =
        Map.put(item, "photo_key", mapped_key(item["photo_key"], uploaded, source_bucket))

      put_identified(Modifier, attrs, @modifier_fields ++ [:group_id], &Modifier.changeset/2, [
        :photo_key
      ])
    end)

    Enum.each(data["links"], fn item ->
      existing =
        Repo.get_by(ProductModifierGroup,
          product_id: item["product_id"],
          group_id: item["group_id"]
        )

      changes =
        Ecto.Changeset.change(
          existing ||
            %ProductModifierGroup{product_id: item["product_id"], group_id: item["group_id"]},
          position: item["position"]
        )

      save!(changes)
    end)
  end

  defp apply_franchise_data(data, branches, uploaded, sections) do
    Enum.each(data["branches"], fn entry ->
      target_id = Map.fetch!(branches, entry["branch_id"])
      put_branch!(Repo.get!(Branch, target_id), entry["branch"])

      if :storefront in sections do
        put_info(target_id, entry["info"])
        put_delivery(target_id, entry)
      end

      if :catalog in sections do
        apply_catalog(target_id, entry, uploaded, data["public_bucket"])
        Delivest.Net.Catalogs.clear_menu_cache(target_id)
      end

      if :integrations in sections do
        put_branch_integrations(target_id, entry["integrations"])
      end
    end)

    if :franchise in sections do
      put_franchise(
        data["franchise"],
        uploaded,
        data["public_bucket"],
        franchise_fields(sections)
      )

      put_documents(data["documents"])
    end

    if :integrations in sections do
      put_global_integrations(data["integrations"])
    end
  end

  defp franchise_fields(sections) do
    if :integrations in sections,
      do: @franchise_fields ++ @franchise_integration_fields,
      else: @franchise_fields
  end

  defp abort!(reason), do: throw({:snapshot_abort, reason})

  defp put_record(record, attrs, fun) do
    record |> fun.(attrs) |> save!()
  end

  defp put_identified(schema, item, fields, fun, extra \\ []) do
    old = Repo.get(schema, item["id"])
    attrs = Map.take(item, Enum.map(fields, &Atom.to_string/1))
    changes = fun.(old || struct(schema, id: item["id"]), attrs)

    changes =
      Enum.reduce(extra, changes, fn field, acc ->
        Ecto.Changeset.put_change(acc, field, Map.get(attrs, Atom.to_string(field)))
      end)

    save!(changes)
  end

  defp save!(changeset) do
    case Repo.insert_or_update(changeset) do
      {:ok, record} -> record
      {:error, reason} -> abort!(reason)
    end
  end

  defp assert_unshared!(type, id, branch_id) do
    schema = if type == "Category", do: Category, else: Product
    existing = Repo.get(schema, id)
    if existing && !Relations.related?("Branch", branch_id, type, id), do: abort!(:id_collision)

    other =
      Repo.exists?(
        from r in Delivest.Relations.EntityRelation,
          where:
            r.to_entity_type == ^type and r.to_id == ^id and r.from_entity_type == "Branch" and
              r.from_id != ^branch_id
      )

    if other, do: abort!(:shared_catalog_conflict)
  end

  defp assert_group_unshared!(id, branch_id) do
    existing = Repo.get(ModifierGroup, id)

    if existing &&
         !Repo.exists?(
           from l in ProductModifierGroup,
             join: r in Delivest.Relations.EntityRelation,
             on:
               r.to_id == l.product_id and r.to_entity_type == "Product" and
                 r.from_entity_type == "Branch",
             where: l.group_id == ^id and r.from_id == ^branch_id
         ),
       do: abort!(:id_collision)

    other =
      Repo.exists?(
        from l in ProductModifierGroup,
          join: r in Delivest.Relations.EntityRelation,
          on:
            r.to_id == l.product_id and r.to_entity_type == "Product" and
              r.from_entity_type == "Branch",
          where: l.group_id == ^id and r.from_id != ^branch_id
      )

    if other, do: abort!(:shared_catalog_conflict)
  end

  defp assert_tag_unshared!(id, branch_id) do
    existing = Repo.get(ProductTag, id)

    if existing &&
         !Repo.exists?(
           from p in Product,
             join: r in Delivest.Relations.EntityRelation,
             on:
               r.to_id == p.id and r.to_entity_type == "Product" and
                 r.from_entity_type == "Branch",
             where: ^id in p.tags and r.from_id == ^branch_id
         ),
       do: abort!(:id_collision)

    other =
      Repo.exists?(
        from p in Product,
          join: r in Delivest.Relations.EntityRelation,
          on:
            r.to_id == p.id and r.to_entity_type == "Product" and r.from_entity_type == "Branch",
          where: ^id in p.tags and r.from_id != ^branch_id
      )

    if other, do: abort!(:shared_catalog_conflict)
  end

  defp assert_modifier_owned!(id, group_id, branch_id) do
    if Repo.get(Modifier, id) &&
         !Repo.exists?(
           from l in ProductModifierGroup,
             join: r in Delivest.Relations.EntityRelation,
             on:
               r.to_id == l.product_id and r.to_entity_type == "Product" and
                 r.from_entity_type == "Branch",
             where: l.group_id == ^group_id and r.from_id == ^branch_id
         ),
       do: abort!(:id_collision)
  end

  defp relate(branch_id, type, id) do
    case Relations.create_relation(Repo, "Branch", branch_id, type, id) do
      {:ok, _} -> :ok
      {:error, reason} -> abort!(reason)
    end
  end

  defp put_info(branch_id, attrs) do
    current = Repo.get_by(BranchInfo, branch_id: branch_id) || %BranchInfo{branch_id: branch_id}

    safe =
      Map.take(
        attrs,
        Enum.map(@info_fields, &Atom.to_string/1) ++ ~w(fulfillment kitchen loyalty)
      )

    changes = BranchInfo.changeset(current, safe)
    save!(Ecto.Changeset.put_change(changes, :special_hours, attrs["special_hours"] || %{}))
  end

  defp put_franchise(attrs, uploaded, source_bucket, fields \\ @franchise_fields) do
    current = Repo.one(FranchiseSettings) || %FranchiseSettings{}
    safe = Map.take(attrs, Enum.map(fields, &Atom.to_string/1))
    public = Map.drop(safe, Enum.map(@image_fields, &Atom.to_string/1))
    changes = FranchiseSettings.changeset(current, public)

    changes =
      Enum.reduce(@image_fields, changes, fn field, acc ->
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
    Enum.each(documents, fn document ->
      kind = document_kind(document["kind"])
      current = Repo.get_by(LegalDocument, kind: kind) || %LegalDocument{kind: kind}
      save!(LegalDocument.changeset(current, %{kind: kind, body: document["body"]}))
    end)
  end

  defp put_global_integrations(integrations) do
    Enum.each(integrations, fn {key, attrs} ->
      {module, _fields} = global_integration_schema(key)
      current = Repo.one(module) || struct(module)
      save!(module.changeset(current, attrs))
    end)
  end

  defp put_delivery(branch_id, data) do
    settings = Delivery.get_settings(branch_id)

    attrs =
      Map.take(
        data["delivery_settings"],
        Enum.map(@settings_fields, &Atom.to_string/1) ++ ["thresholds"]
      )

    put_record(settings, attrs, &Settings.changeset/2)

    Enum.each(data["zones"], fn item ->
      old = Repo.get(Zone, item["id"])
      if old && old.branch_id != branch_id, do: abort!(:zone_conflict)
      zone = old || %Zone{id: item["id"], branch_id: branch_id}

      changes =
        Zone.changeset(
          zone,
          Map.take(item, Enum.map(@zone_fields, &Atom.to_string/1) ++ ["thresholds"])
        )

      changes =
        changes
        |> Ecto.Changeset.put_change(:polygon, item["polygon"])
        |> Ecto.Changeset.put_change(:radius_km, item["radius_km"])

      save!(changes)
    end)
  end

  defp mapped_key(nil, _uploaded, _source_bucket), do: nil

  defp mapped_key(key, uploaded, source_bucket) do
    case Map.fetch(uploaded, "#{source_bucket}/#{key}") do
      {:ok, new_key} -> new_key
      :error -> abort!(:missing_media)
    end
  end
end
