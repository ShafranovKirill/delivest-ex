defmodule Delivest.Integrations.Iiko.Settings do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key false
  embedded_schema do
    field :api_key, :string, redact: true
    field :organization_id, :string
    field :terminal_group_id, :string
    field :webhook_token, :string, redact: true
    field :sync_stops, :boolean, default: false
    field :cash_payment_type_id, :string
    field :card_payment_type_id, :string
    field :online_payment_type_id, :string
  end

  def changeset(settings, attrs, required? \\ false) do
    settings
    |> cast(attrs, [
      :api_key,
      :organization_id,
      :terminal_group_id,
      :sync_stops,
      :cash_payment_type_id,
      :card_payment_type_id,
      :online_payment_type_id
    ])
    |> keep_api_key(settings)
    |> update_change(:api_key, &String.trim/1)
    |> put_webhook_token()
    |> then(
      &if(required?,
        do: validate_required(&1, [:api_key, :organization_id, :terminal_group_id]),
        else: &1
      )
    )
  end

  defp keep_api_key(changeset, %{api_key: key}) when is_binary(key) do
    case get_change(changeset, :api_key) do
      value when value in [nil, ""] -> put_change(changeset, :api_key, key)
      _value -> changeset
    end
  end

  defp keep_api_key(changeset, _settings), do: changeset

  defp put_webhook_token(changeset) do
    if get_field(changeset, :webhook_token),
      do: changeset,
      else: put_change(changeset, :webhook_token, token())
  end

  defp token, do: 24 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
end
