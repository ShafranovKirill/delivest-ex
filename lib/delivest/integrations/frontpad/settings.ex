defmodule Delivest.Integrations.Frontpad.Settings do
  use Ecto.Schema
  import Ecto.Changeset

  alias Delivest.Integrations.Frontpad.{PaymentCodes, StatusCodes, TagCodes}

  @type t :: %__MODULE__{}

  @primary_key false
  embedded_schema do
    field :api_key, :string, redact: true
    field :affiliate, :string
    field :webhook_token, :string, redact: true
    field :price_override, :boolean, default: false
    field :sync_stops, :boolean, default: false
    field :delivery_article, :string
    embeds_one :statuses, StatusCodes, on_replace: :update
    embeds_one :payments, PaymentCodes, on_replace: :update
    embeds_one :tags, TagCodes, on_replace: :update
  end

  def changeset(settings, attrs, required? \\ false) do
    settings
    |> cast(attrs, [:api_key, :affiliate, :price_override, :sync_stops, :delivery_article])
    |> cast_embed(:statuses)
    |> cast_embed(:payments)
    |> cast_embed(:tags)
    |> validate_format(:delivery_article, ~r/^\d+$/)
    |> put_webhook_token()
    |> then(&if(required?, do: validate_required(&1, [:api_key]), else: &1))
  end

  defp put_webhook_token(changeset) do
    if get_field(changeset, :webhook_token),
      do: changeset,
      else: put_change(changeset, :webhook_token, token())
  end

  defp token, do: 24 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
end
