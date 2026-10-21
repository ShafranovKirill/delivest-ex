defmodule Delivest.Integrations.Frontpad.Settings do
  use Ecto.Schema
  import Ecto.Changeset

  alias Delivest.Integrations.Frontpad.StatusCodes

  @type t :: %__MODULE__{}

  @primary_key false
  embedded_schema do
    field :api_key, :string, redact: true
    field :affiliate, :string
    field :webhook_token, :string, redact: true
    field :price_override, :boolean, default: false
    embeds_one :statuses, StatusCodes, on_replace: :update
  end

  def changeset(settings, attrs, required? \\ false) do
    settings
    |> cast(attrs, [:api_key, :affiliate, :price_override])
    |> cast_embed(:statuses)
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
