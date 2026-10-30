defmodule Delivest.Integrations.Zvonok.Settings do
  use Ecto.Schema
  import Ecto.Changeset

  use Gettext, backend: DelivestWeb.Gettext

  @type t :: %__MODULE__{}

  @modes [:inbound, :flash]
  @fields [:public_key, :campaign_id, :webhook_token]

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "zvonok_settings" do
    field :public_key, :string, redact: true
    field :campaign_id, :string
    field :webhook_token, :string, redact: true
    field :enabled, :boolean, default: true
    field :login_call_mode, Ecto.Enum, values: @modes, default: :inbound

    timestamps(type: :utc_datetime)
  end

  def changeset(settings, attrs) do
    settings
    |> cast(attrs, [:enabled, :login_call_mode | @fields], empty_values: [nil, ""])
    |> update_change(:public_key, &String.trim/1)
    |> update_change(:campaign_id, &String.trim/1)
    |> update_change(:webhook_token, &String.trim/1)
    |> put_webhook_token()
    |> validate_required_when_enabled()
    |> validate_format(:webhook_token, ~r/^[A-Za-z0-9_-]{8,}$/,
      message: gettext("At least 8 latin letters, digits, - or _")
    )
  end

  def modes, do: @modes

  def complete?(%__MODULE__{} = settings),
    do: Enum.all?(@fields, &(Map.get(settings, &1) not in [nil, ""]))

  defp validate_required_when_enabled(changeset) do
    if get_field(changeset, :enabled),
      do: validate_required(changeset, @fields),
      else: changeset
  end

  defp put_webhook_token(changeset) do
    if get_field(changeset, :webhook_token),
      do: changeset,
      else: put_change(changeset, :webhook_token, token())
  end

  defp token, do: 24 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
end
