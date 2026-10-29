defmodule Delivest.Identity.Branch.BranchInfo do
  use Ecto.Schema
  import Ecto.Changeset
  alias Delivest.Identity.Branch.{CourierSettings, KitchenSettings, YcartSettings}
  alias Delivest.Integrations.Crm.BranchSettings
  alias Delivest.Identity

  use Gettext, backend: DelivestWeb.Gettext

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "branch_info" do
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
    field :board_token, :string
    embeds_one :crm, BranchSettings, on_replace: :update
    embeds_one :channels, Delivest.Integrations.Channels.BranchSettings, on_replace: :update
    embeds_one :ycart_settings, YcartSettings, on_replace: :update
    embeds_one :kitchen, KitchenSettings, on_replace: :update, defaults_to_struct: true
    embeds_one :couriers, CourierSettings, on_replace: :update, defaults_to_struct: true

    embeds_one :yandex_delivery, Delivest.Integrations.YandexDelivery.Settings,
      on_replace: :update

    belongs_to :branch, Delivest.Identity.Branch

    timestamps()
  end

  def board_token_changeset(branch_info, token) do
    branch_info
    |> change(board_token: token)
    |> unique_constraint(:board_token)
  end

  def changeset(branch_info, attrs) do
    branch_info
    |> cast(attrs, [
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
      :branch_id
    ])
    |> cast_embed(:crm, with: &BranchSettings.changeset/2)
    |> cast_embed(:channels, with: &Delivest.Integrations.Channels.BranchSettings.changeset/2)
    |> cast_embed(:ycart_settings, with: &YcartSettings.changeset/2)
    |> cast_embed(:kitchen, with: &KitchenSettings.changeset/2)
    |> cast_embed(:couriers, with: &CourierSettings.changeset/2)
    |> cast_embed(:yandex_delivery,
      with: &Delivest.Integrations.YandexDelivery.Settings.changeset/2
    )
    |> validate_required([:branch_id])
    |> validate_length(:city, max: 100)
    |> validate_number(:latitude, greater_than_or_equal_to: -90, less_than_or_equal_to: 90)
    |> validate_number(:longitude, greater_than_or_equal_to: -180, less_than_or_equal_to: 180)
    |> validate_format(:phone_number, Identity.phone_regex(),
      message:
        dgettext_noop(
          "errors",
          "The number must be in the format +7XXXXXXXXXX"
        )
    )
  end

  def phone_regex, do: ~r/^\+7\d{10}$/
end
