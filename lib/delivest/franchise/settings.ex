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
    field :primary_color, :string, default: "#48010c"
    field :dark_primary_color, :string
    field :default_theme, :string, default: "light"
    field :legal_form, :string
    field :legal_name, :string
    field :inn, :string
    field :ogrn, :string
    field :legal_address, :string
    field :email, :string
    field :phone, :string
    field :timezone, :string, default: "Europe/Moscow"
    field :yandex_org_id, :string
    field :yandex_api_key, :string, redact: true
    field :loyalty_per_rubles, :integer, default: 100
    field :loyalty_stars, :integer, default: 5
    field :loyalty_expire_days, :integer, default: 180
    field :icon_key, :string
    field :share_image_key, :string
    field :logo_key, :string
    field :logo_dark_key, :string
    field :client_auth_required, :boolean, default: false

    timestamps(type: :utc_datetime)
  end

  def changeset(settings, attrs) do
    settings
    |> cast(attrs, fields(), empty_values: [nil, ""])
    |> update_change(:primary_color, &downcase/1)
    |> update_change(:dark_primary_color, &downcase/1)
    |> validate_required([:name, :primary_color, :default_theme, :timezone])
    |> validate_default_theme_input(attrs)
    |> validate_inclusion(:default_theme, ["light", "dark"])
    |> validate_client_auth_available()
    |> Delivest.LocalTime.validate_timezone(:timezone)
    |> validate_number(:loyalty_per_rubles, greater_than: 0, less_than_or_equal_to: 100_000)
    |> validate_number(:loyalty_stars, greater_than: 0, less_than_or_equal_to: 100_000)
    |> validate_number(:loyalty_expire_days, greater_than: 0, less_than_or_equal_to: 3650)
    |> validate_length(:name, max: 60)
    |> validate_length(:description, max: 300)
    |> validate_length(:yandex_org_id, max: 40)
    |> validate_length(:legal_form, max: 20)
    |> validate_length(:legal_name, max: 200)
    |> validate_length(:legal_address, max: 300)
    |> validate_format(:primary_color, @color_format, message: gettext("Use the #RRGGBB format"))
    |> validate_format(:dark_primary_color, @color_format,
      message: gettext("Use the #RRGGBB format")
    )
    |> validate_format(:inn, ~r/^(\d{10}|\d{12})$/, message: gettext("10 or 12 digits"))
    |> validate_format(:ogrn, ~r/^(\d{13}|\d{15})$/, message: gettext("13 or 15 digits"))
    |> validate_format(:email, @email_format, message: gettext("Not an email"))
  end

  def images_changeset(settings, attrs),
    do: cast(settings, attrs, [:icon_key, :share_image_key, :logo_key, :logo_dark_key])

  def ratings_changeset(settings, attrs) do
    settings
    |> cast(attrs, [:yandex_org_id, :yandex_api_key])
    |> validate_length(:yandex_org_id, max: 40)
  end

  defp downcase(nil), do: nil
  defp downcase(value), do: String.downcase(value)

  defp validate_default_theme_input(changeset, attrs) do
    theme = Map.get(attrs, :default_theme, Map.get(attrs, "default_theme", :absent))

    if theme in [nil, ""] do
      add_error(changeset, :default_theme, "can't be blank", validation: :required)
    else
      changeset
    end
  end

  defp fields do
    [
      :name,
      :timezone,
      :description,
      :primary_color,
      :dark_primary_color,
      :default_theme,
      :legal_form,
      :legal_name,
      :inn,
      :ogrn,
      :legal_address,
      :email,
      :phone,
      :yandex_org_id,
      :yandex_api_key,
      :loyalty_per_rubles,
      :loyalty_stars,
      :loyalty_expire_days,
      :client_auth_required
    ]
  end

  defp validate_client_auth_available(changeset) do
    if get_change(changeset, :client_auth_required) == true do
      zvonok = Delivest.Integrations.Zvonok.get_settings()

      if zvonok.enabled and Delivest.Integrations.Zvonok.Settings.complete?(zvonok) do
        changeset
      else
        add_error(
          changeset,
          :client_auth_required,
          gettext("Sign-in must be configured and enabled before requiring it for checkout")
        )
      end
    else
      changeset
    end
  end
end
