defmodule Delivest.Integrations.YandexAds.Settings do
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, :integer, autogenerate: false}
  @flags ~w(enabled privacy_approved browser_enabled conversions_enabled ecommerce_enabled feed_enabled costs_enabled)a
  @secrets ~w(direct_token metrika_token refresh_token measurement_token oauth_client_secret)a

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
    field :direct_token, :string, source: :direct_token_plain, redact: true
    field :metrika_token, :string, source: :metrika_token_plain, redact: true
    field :refresh_token, :string, source: :refresh_token_plain, redact: true
    field :measurement_token, :string, source: :measurement_token_plain, redact: true
    field :legacy_direct_token, :binary, source: :direct_token, redact: true
    field :legacy_metrika_token, :binary, source: :metrika_token, redact: true
    field :legacy_refresh_token, :binary, source: :refresh_token, redact: true
    field :legacy_measurement_token, :binary, source: :measurement_token, redact: true
    field :oauth_client_id, :string
    field :oauth_client_secret, :string, redact: true
    field :generation, :integer, default: 1
    field :credential_error, :boolean, virtual: true, default: false
    field :credential_errors, {:array, :string}, virtual: true, default: []
    field :cost_feature_generations, :map, virtual: true
    field :costs_refreshed_at, :utc_datetime_usec
    field :costs_from, :date
    field :costs_to, :date
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(settings, attrs) do
    attrs =
      Enum.reject(attrs, fn {key, value} ->
        to_string(key) in Enum.map(@secrets, &to_string/1) and blank_secret?(value)
      end)
      |> Map.new()

    settings
    |> cast(
      attrs,
      @flags ++
        @secrets ++
        [
          :branch_ids,
          :counter_id,
          :goal,
          :client_login,
          :oauth_client_id,
          :currency,
          :timezone,
          :include_vat
        ]
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
    |> validate_length(:oauth_client_id, max: 512)
    |> validate_length(:oauth_client_secret, max: 4096)
    |> validate_required([:goal, :currency, :timezone])
    |> validate_change(:timezone, fn :timezone, zone ->
      case DateTime.shift_zone(DateTime.utc_now(), zone) do
        {:ok, _} -> []
        _ -> [timezone: "is invalid"]
      end
    end)
    |> validate_enabled()
  end

  defp blank_secret?(nil), do: true
  defp blank_secret?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank_secret?(_), do: false

  defp validate_enabled(changeset) do
    if get_field(changeset, :enabled) do
      changeset = validate_required(changeset, [:branch_ids])

      changeset =
        if Enum.any?(
             [:browser_enabled, :conversions_enabled, :ecommerce_enabled],
             &get_field(changeset, &1)
           ), do: validate_required(changeset, [:counter_id]), else: changeset

      changeset =
        if get_field(changeset, :conversions_enabled) and
             (changed?(changeset, :enabled) or changed?(changeset, :conversions_enabled)),
           do: validate_required(changeset, [:metrika_token]),
           else: changeset

      changeset =
        if get_field(changeset, :ecommerce_enabled) and
             (changed?(changeset, :enabled) or changed?(changeset, :ecommerce_enabled)),
           do: validate_required(changeset, [:measurement_token]),
           else: changeset

      if get_field(changeset, :costs_enabled) and
           (changed?(changeset, :enabled) or changed?(changeset, :costs_enabled)),
         do: validate_required(changeset, [:direct_token]),
         else: changeset
    else
      changeset
    end
  end
end
