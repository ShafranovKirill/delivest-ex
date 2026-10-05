defmodule DelivestWeb.Staff.BranchLive.BranchForm do
  use Ecto.Schema
  import Ecto.Changeset
  alias Delivest.Identity.Branch.{FrontpadSettings, YcartSettings}
  alias Delivest.Identity
  alias Delivest.Repo

  use Gettext, backend: DelivestWeb.Gettext

  @primary_key false
  embedded_schema do
    field :name, :string
    field :slug, :string
    field :is_active, :boolean

    field :address, :string
    field :phone_number, :string
    field :delivery_time, :integer
    field :working_hours, :map, default: %{}
    field :vk_url, :string
    field :whatsapp_url, :string
    field :instagram_url, :string
    field :frontpad_api_key, :string
    field :frontpad_enabled, :boolean, default: false

    embeds_one :frontpad_settings, FrontpadSettings, on_replace: :update
    embeds_one :ycart_settings, YcartSettings, on_replace: :update
  end

  def changeset(form, attrs) do
    attrs = normalize_working_hours_attrs(attrs)

    form
    |> cast(attrs, [
      :name,
      :address,
      :phone_number,
      :delivery_time,
      :working_hours,
      :vk_url,
      :whatsapp_url,
      :instagram_url,
      :frontpad_api_key,
      :frontpad_enabled,
      :slug,
      :is_active
    ])
    |> cast_embed(:frontpad_settings, with: &FrontpadSettings.changeset/2)
    |> cast_embed(:ycart_settings, with: &YcartSettings.changeset/2)
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
      phone_number: info && info.phone_number,
      delivery_time: info && info.delivery_time,
      working_hours: (info && info.working_hours) || %{},
      vk_url: info && info.vk_url,
      whatsapp_url: info && info.whatsapp_url,
      instagram_url: info && info.instagram_url,
      frontpad_api_key: info && info.frontpad_api_key,
      frontpad_enabled: info && info.frontpad_enabled,
      frontpad_settings: info && info.frontpad_settings,
      ycart_settings: info && info.ycart_settings
    }
  end

  defp normalize_working_hours_attrs(%{"working_hours" => working_hours} = attrs)
       when is_map(working_hours) do
    Map.put(attrs, "working_hours", normalize_working_hours_map(working_hours))
  end

  defp normalize_working_hours_attrs(attrs), do: attrs

  defp normalize_working_hours_map(map) when is_map(map) do
    Enum.reduce(map, %{}, fn {day, schedule}, acc ->
      normalized_schedule =
        case schedule do
          %{} = schedule_map ->
            schedule_map
            |> Enum.reject(fn {key, _value} -> String.starts_with?(to_string(key), "_unused_") end)
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

    frontpad_settings_param =
      case data.frontpad_settings do
        %FrontpadSettings{} = settings -> Map.from_struct(settings) |> Map.delete(:__struct__)
        map when is_map(map) -> map
        _ -> %{}
      end

    ycart_settings_param =
      case data.ycart_settings do
        %YcartSettings{} = settings -> Map.from_struct(settings) |> Map.delete(:__struct__)
        map when is_map(map) -> map
        _ -> %{}
      end

    info_params =
      data
      |> Map.take([
        :address,
        :phone_number,
        :delivery_time,
        :working_hours,
        :vk_url,
        :whatsapp_url,
        :instagram_url,
        :frontpad_api_key,
        :frontpad_enabled
      ])
      |> Map.new(fn {k, v} -> {Atom.to_string(k), v} end)
      |> Map.put("frontpad_settings", frontpad_settings_param)
      |> Map.put("ycart_settings", ycart_settings_param)

    {branch_params, info_params}
  end
end
