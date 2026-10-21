defmodule Delivest.Franchise.Settings do
  use Ecto.Schema
  import Ecto.Changeset

  use Gettext, backend: DelivestWeb.Gettext

  @type t :: %__MODULE__{}

  @color_format ~r/^#[0-9a-fA-F]{6}$/
  @email_format ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "franchise_settings" do
    field :name, :string, default: "Delivest"
    field :description, :string
    field :primary_color, :string, default: "#462094"
    field :legal_form, :string
    field :legal_name, :string
    field :inn, :string
    field :ogrn, :string
    field :legal_address, :string
    field :email, :string
    field :phone, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(settings, attrs) do
    settings
    |> cast(attrs, fields(), empty_values: [nil, ""])
    |> update_change(:primary_color, &String.downcase/1)
    |> validate_required([:name, :primary_color])
    |> validate_length(:name, max: 60)
    |> validate_length(:description, max: 300)
    |> validate_length(:legal_form, max: 20)
    |> validate_length(:legal_name, max: 200)
    |> validate_length(:legal_address, max: 300)
    |> validate_format(:primary_color, @color_format, message: gettext("Use the #RRGGBB format"))
    |> validate_format(:inn, ~r/^(\d{10}|\d{12})$/, message: gettext("10 or 12 digits"))
    |> validate_format(:ogrn, ~r/^(\d{13}|\d{15})$/, message: gettext("13 or 15 digits"))
    |> validate_format(:email, @email_format, message: gettext("Not an email"))
  end

  defp fields do
    [
      :name,
      :description,
      :primary_color,
      :legal_form,
      :legal_name,
      :inn,
      :ogrn,
      :legal_address,
      :email,
      :phone
    ]
  end
end
