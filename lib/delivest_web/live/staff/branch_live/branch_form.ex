defmodule DelivestWeb.Staff.BranchLive.BranchForm do
  use Ecto.Schema
  import Ecto.Changeset
  alias Delivest.Identity.Branch.{CourierSettings, KitchenSettings, YcartSettings}
  alias Delivest.Identity
  alias Delivest.Repo

  use Gettext, backend: DelivestWeb.Gettext

  @primary_key false
  embedded_schema do
    field :name, :string
    field :slug, :string
    field :is_active, :boolean

    field :address, :string
    field :city, :string
    field :latitude, :float
    field :longitude, :float
    field :phone_number, :string
    field :delivery_time, :integer
    field :working_hours, :map, default: %{}
    field :vk_url, :string
    field :whatsapp_url, :string
    field :instagram_url, :string

    embeds_one :ycart_settings, YcartSettings, on_replace: :update
    embeds_one :kitchen, KitchenSettings, on_replace: :update
    embeds_one :couriers, CourierSettings, on_replace: :update
  end

  def changeset(form, attrs) do
    attrs = normalize_working_hours_attrs(form, attrs)

    form
    |> cast(attrs, [
      :name,
      :address,
      :city,
      :latitude,
      :longitude,
      :phone_number,
      :delivery_time,
      :working_hours,
      :vk_url,
      :whatsapp_url,
      :instagram_url,
      :slug,
      :is_active
    ])
    |> cast_embed(:ycart_settings, with: &YcartSettings.changeset/2)
    |> cast_embed(:kitchen, with: &KitchenSettings.changeset/2)
    |> cast_embed(:couriers, with: &CourierSettings.changeset/2)
    |> validate_format(:phone_number, Identity.phone_regex(),
      message:
        dgettext_noop(
          "errors",
          "The number must be in the format +7XXXXXXXXXX"
        )
    )
  end

  def from_branch(branch) do
    branch = Repo.preload(branch, :info)
    info = branch.info

    %__MODULE__{
      name: branch.name,
      slug: branch.slug,
      is_active: branch.is_active,
      address: info && info.address,
      city: info && info.city,
      latitude: info && info.latitude,
      longitude: info && info.longitude,
      phone_number: info && info.phone_number,
      delivery_time: info && info.delivery_time,
      working_hours: (info && info.working_hours) || %{},
      vk_url: info && info.vk_url,
      whatsapp_url: info && info.whatsapp_url,
      instagram_url: info && info.instagram_url,
      ycart_settings: (info && info.ycart_settings) || %YcartSettings{},
      kitchen: (info && info.kitchen) || %KitchenSettings{},
      couriers: (info && info.couriers) || %CourierSettings{}
    }
  end

  def new,
    do: %__MODULE__{
      ycart_settings: %YcartSettings{},
      kitchen: %KitchenSettings{},
      couriers: %CourierSettings{}
    }

  def for_branch(%{id: id} = branch) when not is_nil(id), do: from_branch(branch)
  def for_branch(_branch), do: new()

  defp normalize_working_hours_attrs(form, attrs) when is_map(attrs) do
    case Map.fetch(attrs, "working_hours") do
      {:ok, incoming} when is_map(incoming) ->
        working_hours =
          form.working_hours
          |> stringify_map_keys()
          |> deep_merge(stringify_map_keys(incoming))
          |> normalize_working_hours_map()

        Map.put(attrs, "working_hours", working_hours)

      _ ->
        case Map.fetch(attrs, :working_hours) do
          {:ok, incoming} when is_map(incoming) ->
            working_hours =
              form.working_hours
              |> stringify_map_keys()
              |> deep_merge(stringify_map_keys(incoming))
              |> normalize_working_hours_map()

            Map.put(attrs, :working_hours, working_hours)

          _ ->
            attrs
        end
    end
  end

  defp normalize_working_hours_attrs(_form, attrs), do: attrs

  defp stringify_map_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} ->
      value = if is_map(value), do: stringify_map_keys(value), else: value
      {to_string(key), value}
    end)
  end

  defp stringify_map_keys(_), do: %{}

  defp deep_merge(existing, incoming) do
    Map.merge(existing, incoming, fn _key, existing_value, incoming_value ->
      if is_map(existing_value) and is_map(incoming_value) do
        deep_merge(existing_value, incoming_value)
      else
        incoming_value
      end
    end)
  end

  defp normalize_working_hours_map(map) when is_map(map) do
    Enum.reduce(map, %{}, fn {day, schedule}, acc ->
      normalized_schedule =
        case schedule do
          %{} = schedule_map ->
            schedule_map
            |> Enum.reject(fn {key, _value} ->
              String.starts_with?(to_string(key), "_unused_")
            end)
            |> Enum.reduce(%{}, fn {key, value}, day_acc ->
              normalized_value =
                case key do
                  "enabled" ->
                    case value do
                      "true" -> true
                      "false" -> false
                      "on" -> true
                      "off" -> false
                      true -> true
                      false -> false
                      _ -> value
                    end

                  _ ->
                    if value in ["", nil], do: nil, else: value
                end

              Map.put(day_acc, key, normalized_value)
            end)

          _ ->
            %{}
        end

      Map.put(acc, day, normalized_schedule)
    end)
  end

  def to_params(changeset) do
    data = apply_changes(changeset)

    branch_params =
      data
      |> Map.take([:name, :slug, :is_active])
      |> Enum.reject(fn {_, v} -> is_nil(v) end)
      |> Map.new(fn {k, v} -> {Atom.to_string(k), v} end)

    info_params =
      data
      |> Map.take([
        :address,
        :city,
        :latitude,
        :longitude,
        :phone_number,
        :delivery_time,
        :working_hours,
        :vk_url,
        :whatsapp_url,
        :instagram_url
      ])
      |> Map.new(fn {k, v} -> {Atom.to_string(k), v} end)
      |> Map.put("ycart_settings", embed_params(data.ycart_settings))
      |> Map.put("kitchen", embed_params(data.kitchen))
      |> Map.put("couriers", embed_params(data.couriers))

    {branch_params, info_params}
  end

  defp embed_params(nil), do: %{}
  defp embed_params(embed), do: params_value(embed)

  defp params_value(%_{} = embed) do
    embed
    |> Map.from_struct()
    |> Map.new(fn {key, value} -> {Atom.to_string(key), params_value(value)} end)
  end

  defp params_value(value), do: value
end
