defmodule Delivest.SiteSnapshot.Fields do
  @moduledoc """
  One list of transferable fields per snapshot section.

  Export, archive validation and the import writer all read these lists, so a
  field cannot be exported without being validated or written silently.
  """

  @sections [:storefront, :catalog, :franchise, :integrations]

  @branch_fields ~w(name is_active)a
  @franchise_branch_fields ~w(name slug code is_active)a

  @info_fields ~w(address city latitude longitude phone_number delivery_time working_hours special_hours vk_url whatsapp_url instagram_url timezone)a

  @franchise_fields ~w(name description primary_color dark_primary_color timezone legal_form legal_name inn ogrn legal_address email phone loyalty_per_rubles loyalty_stars loyalty_expire_days icon_key share_image_key logo_key logo_dark_key)a
  @image_fields ~w(icon_key share_image_key logo_key logo_dark_key)a

  @category_fields ~w(name order is_active)a
  @product_fields ~w(name slug old_price price description quantity weight measure_unit calories proteins fats carbohydrates excise vat is_active tags suggested stars_price stars_reward order)a
  @group_fields ~w(name min max position is_active is_size)a
  @modifier_fields ~w(name price max_quantity is_default weight position is_active photo_key)a
  @tag_fields ~w(name icon icon_key order)a
  @zone_fields ~w(name color enabled position polygon radius_km geometry_version delivery_minutes)a
  @settings_fields ~w(mode show_zones outside_zones)a

  @catalog_fields %{
    "categories" => @category_fields,
    "products" => @product_fields,
    "groups" => @group_fields,
    "modifiers" => @modifier_fields,
    "tags" => @tag_fields,
    "media" => ~w(bucket key original_name mime_type size context owner_id is_private)a,
    "links" => ~w(product_id group_id position)a
  }

  @catalog_order ~w(categories groups media tags products modifiers links)

  @branch_integration_fields ~w(crm fiscal channels yandex_delivery ycart_settings)a

  @global_integrations [
    {"yookassa", Delivest.Integrations.Yookassa.Settings, ~w(shop_id secret_key webhook_token)a},
    {"zvonok", Delivest.Integrations.Zvonok.Settings,
     ~w(public_key campaign_id webhook_token enabled dev_skip_calls login_call_mode)a},
    {"dadata", Delivest.Integrations.Dadata.Settings, ~w(api_key enabled)a},
    {"yandex_eda", Delivest.Integrations.YandexEda.Settings,
     ~w(partner_name push_client_id push_client_secret)a}
  ]

  def sections, do: @sections

  def frontpad_catalog_types,
    do: %{"product" => "products", "modifier" => "modifiers", "modifier_group" => "groups"}

  def branch_fields(:branch), do: @branch_fields
  def branch_fields(:franchise), do: @franchise_branch_fields

  def franchise_fields(_sections), do: @franchise_fields

  def franchise_brand_fields, do: @franchise_fields
  def info_fields, do: @info_fields
  def image_fields, do: @image_fields
  def settings_fields, do: @settings_fields
  def zone_fields, do: @zone_fields
  def branch_integration_fields, do: @branch_integration_fields
  def catalog_order, do: @catalog_order

  def catalog_fields(type), do: Map.fetch!(@catalog_fields, type)

  def catalog_types do
    [
      {"categories", Delivest.Net.Category},
      {"groups", Delivest.Net.ModifierGroup},
      {"media", Delivest.Media.File},
      {"tags", Delivest.Net.ProductTag},
      {"products", Delivest.Net.Product},
      {"modifiers", Delivest.Net.Modifier}
    ]
  end

  def catalog_schemas do
    Map.new(catalog_types(), fn {type, schema} -> {type, schema} end)
    |> Map.put("zones", Delivest.Delivery.Zone)
  end

  def global_integrations, do: @global_integrations

  def fields(nil, _keys), do: %{}

  def fields(struct, keys),
    do: Map.new(keys, fn key -> {Atom.to_string(key), Map.get(struct, key)} end)

  def record(struct, keys), do: Map.put(fields(struct, keys), "id", struct.id)

  def take(attrs, keys) when is_map(attrs),
    do: Map.take(attrs, Enum.map(keys, &Atom.to_string/1))

  def embed_map(nil), do: nil
  def embed_map(struct), do: encode_value(struct)

  def encode_value(%_{} = struct), do: struct |> Map.from_struct() |> encode_value()

  def encode_value(map) when is_map(map),
    do: Map.new(map, fn {key, value} -> {to_string(key), encode_value(value)} end)

  def encode_value(list) when is_list(list), do: Enum.map(list, &encode_value/1)
  def encode_value(value), do: value

  def thresholds(items) do
    Enum.map(items || [], &fields(&1, ~w(order_from price)a))
  end

  def info(nil), do: %{}

  def info(info) do
    Map.merge(fields(info, @info_fields), %{
      "fulfillment" => fields(info.fulfillment, ~w(delivery pickup dine_in)a),
      "kitchen" => fields(info.kitchen, ~w(enabled lead_minutes)a),
      "loyalty" => fields(info.loyalty, ~w(shop_enabled enabled spend_enabled max_percent)a)
    })
  end

  def branch_integrations(nil),
    do:
      Map.new(
        ~w(crm fiscal channels yandex_delivery ycart_settings)a,
        &{to_string(&1), nil}
      )

  def branch_integrations(info) do
    Map.new(@branch_integration_fields, fn field ->
      {Atom.to_string(field), embed_map(Map.get(info, field))}
    end)
  end

  def valid_record_keys?(record, keys) when is_map(record) do
    MapSet.new(Map.keys(record)) == MapSet.new(Enum.map(keys, &to_string/1))
  end

  def valid_record_keys?(_record, _keys), do: false

  def nested_fields?(parent, key, allowed) do
    case parent[key] do
      value when is_map(value) -> Map.keys(value) -- allowed == []
      nil -> true
      _ -> false
    end
  end

  def threshold_fields?(items) when is_list(items),
    do: Enum.all?(items, &(is_map(&1) and Map.keys(&1) -- ~w(order_from price) == []))

  def threshold_fields?(_), do: false
end
