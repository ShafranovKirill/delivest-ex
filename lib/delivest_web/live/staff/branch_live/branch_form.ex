defmodule DelivestWeb.Staff.BranchLive.BranchForm do
  use Ecto.Schema
  import Ecto.Changeset
  alias Delivest.Identity.Branch.FrontpadSettings
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
    field :vk_url, :string
    field :whatsapp_url, :string
    field :instagram_url, :string
    field :frontpad_api_key, :string
    field :frontpad_enabled, :boolean, default: false

    embeds_one :frontpad_settings, FrontpadSettings, on_replace: :update
  end

  def changeset(form, attrs) do
    form
    |> cast(attrs, [
      :name,
      :address,
      :phone_number,
      :delivery_time,
      :vk_url,
      :whatsapp_url,
      :instagram_url,
      :frontpad_api_key,
      :frontpad_enabled,
      :slug,
      :is_active
    ])
    |> cast_embed(:frontpad_settings, with: &FrontpadSettings.changeset/2)
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
      vk_url: info && info.vk_url,
      whatsapp_url: info && info.whatsapp_url,
      instagram_url: info && info.instagram_url,
      frontpad_api_key: info && info.frontpad_api_key,
      frontpad_enabled: info && info.frontpad_enabled,
      frontpad_settings: info && info.frontpad_settings
    }
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

    info_params =
      data
      |> Map.take([
        :address,
        :phone_number,
        :delivery_time,
        :vk_url,
        :whatsapp_url,
        :instagram_url,
        :frontpad_api_key,
        :frontpad_enabled
      ])
      |> Map.new(fn {k, v} -> {Atom.to_string(k), v} end)
      |> Map.put("frontpad_settings", frontpad_settings_param)

    {branch_params, info_params}
  end
end
