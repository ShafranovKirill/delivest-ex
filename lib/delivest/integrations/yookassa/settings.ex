defmodule Delivest.Integrations.Yookassa.Settings do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @fields [:shop_id, :secret_key]

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "yookassa_settings" do
    field :shop_id, :string
    field :secret_key, :string, redact: true
    field :webhook_token, :string, redact: true

    timestamps(type: :utc_datetime)
  end

  def changeset(settings, attrs) do
    settings
    |> cast(attrs, @fields, empty_values: [nil, ""])
    |> update_change(:shop_id, &trim/1)
    |> update_change(:secret_key, &trim/1)
    |> keep_secret(settings)
    |> validate_required(@fields)
    |> validate_format(:shop_id, ~r/^\d+$/)
    |> put_webhook_token()
  end

  def complete?(%__MODULE__{} = settings),
    do: Enum.all?(@fields, &(Map.get(settings, &1) not in [nil, ""]))

  def complete?(_settings), do: false

  defp trim(value) when is_binary(value), do: String.trim(value)
  defp trim(value), do: value

  defp keep_secret(changeset, %{secret_key: secret}) when is_binary(secret) do
    if get_change(changeset, :secret_key) in [nil, ""],
      do: put_change(changeset, :secret_key, secret),
      else: changeset
  end

  defp keep_secret(changeset, _settings), do: changeset

  defp put_webhook_token(changeset) do
    if get_field(changeset, :webhook_token),
      do: changeset,
      else:
        put_change(
          changeset,
          :webhook_token,
          24 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
        )
  end
end
