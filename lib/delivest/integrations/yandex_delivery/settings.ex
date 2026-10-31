defmodule Delivest.Integrations.YandexDelivery.Settings do
  use Ecto.Schema
  import Ecto.Changeset

  @taxi_classes [:courier, :express]

  @type t :: %__MODULE__{}

  @primary_key false
  embedded_schema do
    field :token, :string, redact: true
    field :taxi_class, Ecto.Enum, values: @taxi_classes, default: :courier
    field :contact_name, :string
    field :contact_phone, :string
    field :contact_email, :string
    field :confirm_codes, :boolean, default: false
    field :auto_accept, :boolean, default: false
  end

  def taxi_classes, do: @taxi_classes

  def changeset(settings, attrs) do
    settings
    |> cast(keep_token(attrs), [
      :token,
      :taxi_class,
      :contact_name,
      :contact_phone,
      :contact_email,
      :confirm_codes,
      :auto_accept
    ])
    |> update_change(:token, &String.trim/1)
    |> validate_required([:taxi_class])
    |> validate_format(:contact_email, ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/)
    |> validate_format(:contact_phone, ~r/^\+7\d{10}$/)
    |> validate_length(:contact_name, max: 100)
  end

  def configured?(%__MODULE__{token: token, contact_email: email}),
    do: token not in [nil, ""] and email not in [nil, ""]

  def configured?(_settings), do: false

  defp keep_token(%{"token" => token} = attrs) when token in [nil, ""],
    do: Map.delete(attrs, "token")

  defp keep_token(%{token: token} = attrs) when token in [nil, ""], do: Map.delete(attrs, :token)
  defp keep_token(attrs), do: attrs
end
