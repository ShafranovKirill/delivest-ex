defmodule Delivest.SiteSnapshot.Archive do
  @moduledoc """
  ZIP and manifest handling: sizes, checksums, entry names, archive scope and
  the shape of `data.json`. Nothing here writes to the database or S3.
  """

  alias Delivest.Delivery.{Settings, Zone}
  alias Delivest.Franchise.LegalDocument
  alias Delivest.Franchise.Settings, as: FranchiseSettings
  alias Delivest.Identity.Branch
  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Integrations.{Dadata, YandexEda, Yookassa, Zvonok}
  alias Delivest.Media.File, as: MediaFile
  alias Delivest.Net.{Category, Modifier, ModifierGroup, Product, ProductTag}
  alias Delivest.SiteSnapshot.{Assets, Fields}

  @max_archive 100 * 1024 * 1024
  @max_file 20 * 1024 * 1024
  @max_files 1000
  @max_branches 100
  @format 1
  @source_files Path.wildcard("lib/**/*.ex") ++
                  Path.wildcard("priv/repo/migrations/*.exs") ++ ["mix.lock"]
  @source_files Enum.sort(@source_files)
  for path <- @source_files, do: @external_resource(path)

  @build_id :crypto.hash(:sha256, Enum.map(@source_files, &File.read!/1))
            |> Base.encode16(case: :lower)

  def build_id, do: @build_id
  def max_archive, do: @max_archive
  def max_file, do: @max_file
  def max_files, do: @max_files
  def max_branches, do: @max_branches

  def encode(data, blobs, destination, scope) do
    entries =
      Enum.map(blobs, fn {reference, body} ->
        path = "media/" <> Assets.sha(reference)
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
        "data_sha256" => Assets.sha(json),
        "files" =>
          Map.new(entries, fn {path, body, ref} ->
            {path, %{"reference" => ref, "size" => byte_size(body), "sha256" => Assets.sha(body)}}
          end)
      }
      |> then(fn value ->
        if scope == :franchise, do: Map.put(value, "sections", data["sections"]), else: value
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

  def decode(binary, scope) when byte_size(binary) <= @max_archive do
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

  def decode(_, _), do: {:error, :archive_too_large}

  def sections_from_data(_data, :branch), do: [:storefront, :catalog, :franchise]

  def sections_from_data(data, :franchise) when is_map(data) do
    case data["sections"] do
      list when is_list(list) -> Enum.map(list, &section_name/1)
      _ -> []
    end
  end

  def sections_from_data(_data, _scope), do: []

  defp section_name(section) when is_atom(section),
    do: Enum.find(Fields.sections(), &(&1 == section))

  defp section_name(section) when is_binary(section),
    do: Enum.find(Fields.sections(), &(Atom.to_string(&1) == section))

  defp section_name(_), do: nil

  defp installation_id do
    alias Delivest.SiteSnapshot.Installation

    Delivest.Repo.insert(%Installation{id: 1, installation_id: Ecto.UUID.generate()},
      on_conflict: :nothing,
      conflict_target: :id
    )

    Delivest.Repo.get!(Installation, 1).installation_id
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
        manifest["data_sha256"] == Assets.sha(files["data.json"]) and
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
        manifest["data_sha256"] == Assets.sha(files["data.json"]) and
        valid_file_meta?(files, meta)

    if valid?, do: :ok, else: {:error, :invalid_archive}
  end

  defp validate_manifest(%{"build" => build}, _files, _data, _scope) when build != @build_id,
    do: {:error, :different_build}

  defp validate_manifest(_, _, _, _), do: {:error, :invalid_archive}

  defp valid_file_meta?(files, meta) do
    Enum.all?(meta, fn {path, info} ->
      body = files[path]

      is_binary(body) and Assets.image_type(body) != nil and is_map(info) and
        is_binary(info["reference"]) and
        String.starts_with?(path, "media/") and info["size"] == byte_size(body) and
        info["sha256"] == Assets.sha(body) and path == "media/" <> Assets.sha(info["reference"])
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

    branch_fields = Enum.map(Fields.branch_fields(:franchise), &Atom.to_string/1)
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
      Fields.valid_record_keys?(settings, Fields.settings_fields() ++ [:thresholds]) and
      Fields.threshold_fields?(settings["thresholds"]) and
      Settings.changeset(
        %Settings{},
        Fields.take(settings, Fields.settings_fields())
      )
      |> Map.get(:valid?) and
      is_list(zones) and length(zones) <= 10_000 and unique_ids?(zones) and
      Enum.all?(zones, &valid_zone?/1) and
      valid_branch_info?(branch["info"], branch["branch_id"])
  end

  defp valid_zone?(zone) when is_map(zone) do
    Fields.valid_record_keys?(zone, Fields.zone_fields() ++ ["id", "thresholds"]) and
      Fields.threshold_fields?(zone["thresholds"]) and
      Zone.changeset(
        %Zone{},
        Map.take(zone, Enum.map(Fields.zone_fields(), &to_string/1) ++ ["thresholds"])
      ).valid?
  end

  defp valid_zone?(_zone), do: false

  defp valid_branch_info?(%{} = info, _branch_id) when map_size(info) == 0, do: true
  defp valid_branch_info?(info, branch_id), do: valid_info?(info, branch_id)

  defp valid_info?(info, branch_id) when is_map(info) do
    allowed = Enum.map(Fields.info_fields(), &Atom.to_string/1) ++ ~w(fulfillment kitchen loyalty)

    MapSet.new(Map.keys(info)) == MapSet.new(allowed) and
      Fields.nested_fields?(info, "fulfillment", ~w(delivery pickup dine_in)) and
      Fields.nested_fields?(info, "kitchen", ~w(enabled lead_minutes)) and
      Fields.nested_fields?(info, "loyalty", ~w(shop_enabled enabled spend_enabled max_percent)) and
      BranchInfo.changeset(%BranchInfo{branch_id: branch_id}, info).valid?
  end

  defp valid_info?(_info, _branch_id), do: false

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

  defp franchise_part_valid?(data, true, _integrations?) do
    fields = Enum.map(Fields.franchise_fields([:franchise]), &Atom.to_string/1)
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
        MapSet.new(~w(yookassa zvonok dadata yandex_eda yandex_rating))
      ) and
      Enum.all?(integrations, &valid_global_integration?/1)
  end

  defp valid_global_integration?({key, attrs}) when is_map(attrs) do
    case global_integration_schema(key) do
      {module, fields} ->
        MapSet.new(Map.keys(attrs)) == MapSet.new(fields) and
          valid_integration_changeset(module, attrs)

      nil ->
        false
    end
  end

  defp valid_global_integration?(_entry), do: false

  defp valid_integration_changeset(FranchiseSettings, attrs),
    do: FranchiseSettings.ratings_changeset(%FranchiseSettings{}, attrs).valid?

  defp valid_integration_changeset(module, attrs),
    do: module.changeset(struct(module), attrs).valid?

  defp global_integration_schema("yookassa"),
    do: {Yookassa.Settings, ~w(shop_id secret_key webhook_token)}

  defp global_integration_schema("zvonok"),
    do:
      {Zvonok.Settings,
       ~w(public_key campaign_id webhook_token enabled dev_skip_calls login_call_mode)}

  defp global_integration_schema("dadata"), do: {Dadata.Settings, ~w(api_key enabled)}

  defp global_integration_schema("yandex_eda"),
    do: {YandexEda.Settings, ~w(partner_name push_client_id push_client_secret)}

  defp global_integration_schema("yandex_rating"),
    do: {FranchiseSettings, ~w(yandex_org_id yandex_api_key)}

  defp global_integration_schema(_key), do: nil

  defp unique_ids?(records) do
    ids = Enum.map(records, & &1["id"])

    Enum.all?(ids, &(Ecto.UUID.cast(&1) != :error)) and length(ids) == length(Enum.uniq(ids))
  end

  defp valid_fields?(data) do
    allowed = %{
      "branch" => Enum.map(Fields.branch_fields(:branch), &Atom.to_string/1),
      "info" =>
        Enum.map(Fields.info_fields(), &Atom.to_string/1) ++ ~w(fulfillment kitchen loyalty),
      "franchise" => Enum.map(Fields.franchise_fields([:franchise]), &Atom.to_string/1),
      "delivery_settings" =>
        Enum.map(Fields.settings_fields(), &Atom.to_string/1) ++ ["thresholds"],
      "categories" => Enum.map(Fields.catalog_fields("categories"), &Atom.to_string/1) ++ ["id"],
      "products" =>
        Enum.map(Fields.catalog_fields("products"), &Atom.to_string/1) ++
          ~w(id category_id media_id),
      "groups" => Enum.map(Fields.catalog_fields("groups"), &Atom.to_string/1) ++ ["id"],
      "modifiers" =>
        Enum.map(Fields.catalog_fields("modifiers"), &Atom.to_string/1) ++ ~w(id group_id),
      "links" => ~w(product_id group_id position),
      "media" => ~w(id bucket key original_name mime_type size context owner_id is_private),
      "tags" => Enum.map(Fields.catalog_fields("tags"), &Atom.to_string/1) ++ ["id"],
      "zones" => Enum.map(Fields.zone_fields(), &Atom.to_string/1) ++ ~w(id thresholds)
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
      Fields.nested_fields?(data["info"], "fulfillment", ~w(delivery pickup dine_in)) and
      Fields.nested_fields?(data["info"], "kitchen", ~w(enabled lead_minutes)) and
      Fields.nested_fields?(
        data["info"],
        "loyalty",
        ~w(shop_enabled enabled spend_enabled max_percent)
      ) and
      Fields.threshold_fields?(data["delivery_settings"]["thresholds"]) and
      Enum.all?(data["zones"], &Fields.threshold_fields?(&1["thresholds"])) and
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

  defp validate_references(data, manifest, :branch, _sections) do
    public_bucket = data["public_bucket"]
    media_refs = Enum.map(data["media"], &"#{&1["bucket"]}/#{&1["key"]}")
    asset_refs = Enum.map(Assets.branch_keys(data), &"#{public_bucket}/#{&1}")
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
        Enum.map(Assets.franchise_keys(data), &"#{public_bucket}/#{&1}")
      else
        []
      end

    expected = MapSet.new(media_refs ++ asset_refs)
    actual = manifest["files"] |> Map.values() |> Enum.map(& &1["reference"]) |> MapSet.new()
    private? = Enum.any?(data["branches"], &Assets.private_media?/1)

    if expected == actual and not private?, do: :ok, else: {:error, :invalid_archive}
  end

  defp validate_references(_data, _manifest, _scope, _sections),
    do: {:error, :invalid_archive}
end
