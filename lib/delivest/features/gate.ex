defmodule Delivest.Features.Gate do
  use Ecto.Schema

  @primary_key false
  schema "feature_gates" do
    field :feature, :string, primary_key: true
    field :scope_key, :string, primary_key: true
    field :enabled, :boolean, default: false
    field :generation, :integer, default: 0
    timestamps(type: :utc_datetime_usec)
  end
end
