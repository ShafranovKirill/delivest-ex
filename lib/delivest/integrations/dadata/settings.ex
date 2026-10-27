defmodule Delivest.Integrations.Dadata.Settings do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "dadata_settings" do
    field :api_key, :string, redact: true
    field :enabled, :boolean, default: false

    timestamps(type: :utc_datetime)
  end

  def changeset(settings, attrs) do
    settings
    |> cast(attrs, [:api_key, :enabled], empty_values: [nil, ""])
    |> update_change(:api_key, &String.trim/1)
    |> validate_required([:api_key])
  end

  def active?(%__MODULE__{enabled: true, api_key: key}) when is_binary(key) and key != "",
    do: true

  def active?(_settings), do: false
end
