defmodule Delivest.Integrations.YandexAds.Settings do
  use Ecto.Schema
  import Ecto.Changeset
  alias Delivest.Integrations.YandexAds.Secret

  @primary_key {:id, :integer, autogenerate: false}
  @flags ~w(enabled privacy_approved browser_enabled conversions_enabled ecommerce_enabled feed_enabled costs_enabled)a
  @secrets ~w(direct_token metrika_token refresh_token measurement_token)a

  schema "yandex_ads_settings" do
    field :enabled, :boolean, default: false
    field :privacy_approved, :boolean, default: false
    field :browser_enabled, :boolean, default: false
    field :conversions_enabled, :boolean, default: false
    field :ecommerce_enabled, :boolean, default: false
    field :feed_enabled, :boolean, default: false
    field :costs_enabled, :boolean, default: false
    field :branch_ids, {:array, Ecto.UUID}, default: []
    field :counter_id, :string
    field :goal, :string, default: "delivest_order_completed"
    field :client_login, :string
    field :account_scope, :string
    field :currency, :string, default: "RUB"
    field :timezone, :string, default: "Europe/Moscow"
    field :include_vat, :boolean, default: true
    field :direct_token, Secret, redact: true
    field :metrika_token, Secret, redact: true
    field :refresh_token, Secret, redact: true
    field :measurement_token, Secret, redact: true
    field :generation, :integer, default: 1
    field :credential_error, :boolean, virtual: true, default: false
    field :cost_feature_generations, :map, virtual: true
    field :costs_refreshed_at, :utc_datetime_usec
    field :costs_from, :date
    field :costs_to, :date
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(settings, attrs) do
    attrs =
      Enum.reject(attrs, fn {key, value} ->
        to_string(key) in Enum.map(@secrets, &to_string/1) and value in [nil, ""]
      end)
      |> Map.new()

    settings
    |> cast(
      attrs,
      @flags ++
        @secrets ++
        [:branch_ids, :counter_id, :goal, :client_login, :currency, :timezone, :include_vat]
    )
    |> validate_format(:counter_id, ~r/^[1-9][0-9]{0,19}$/)
    |> validate_format(:goal, ~r/^[a-zA-Z][a-zA-Z0-9_-]{0,63}$/)
    |> validate_format(:client_login, ~r/^[a-zA-Z0-9@._-]{1,128}$/)
    |> validate_inclusion(:currency, ["RUB"])
    |> validate_length(:branch_ids, max: 1000)
    |> validate_length(:direct_token, max: 4096)
    |> validate_length(:metrika_token, max: 4096)
    |> validate_length(:measurement_token, max: 4096)
    |> validate_length(:refresh_token, max: 4096)
    |> validate_required([:goal, :currency, :timezone])
    |> validate_change(:timezone, fn :timezone, zone ->
      case DateTime.shift_zone(DateTime.utc_now(), zone) do
        {:ok, _} -> []
        _ -> [timezone: "is invalid"]
      end
    end)
    |> validate_encryption()
    |> validate_enabled()
  end

  defp validate_encryption(changeset) do
    if Enum.any?(@secrets, &changed?(changeset, &1)) and not Secret.configured?(),
      do:
        add_error(
          changeset,
          :direct_token,
          "configure YANDEX_ADS_ENCRYPTION_KEY before saving credentials"
        ),
      else: changeset
  end

  defp validate_enabled(changeset) do
    if get_field(changeset, :enabled) do
      changeset = validate_required(changeset, [:branch_ids])

      changeset =
        if Enum.any?(
             [:browser_enabled, :conversions_enabled, :ecommerce_enabled],
             &get_field(changeset, &1)
           ), do: validate_required(changeset, [:counter_id]), else: changeset

      changeset =
        if get_field(changeset, :conversions_enabled),
          do: validate_required(changeset, [:metrika_token]),
          else: changeset

      changeset =
        if get_field(changeset, :ecommerce_enabled),
          do: validate_required(changeset, [:measurement_token]),
          else: changeset

      if get_field(changeset, :costs_enabled),
        do: validate_required(changeset, [:direct_token]),
        else: changeset
    else
      changeset
    end
  end
end
