defmodule Delivest.Marketing.Issue do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "marketing_issues" do
    belongs_to :policy, Delivest.Marketing.Policy
    belongs_to :client, Delivest.Identity.Client
    field :cycle_order_id, :binary_id
    field :branch_id, :binary_id
    field :reward_type, :string
    field :reward_id, :binary_id
    field :reward_amount, :integer
    field :issued_at, :utc_datetime
    field :expires_at, :utc_datetime
    field :attribution_until, :utc_datetime
    field :policy_revision, :integer
    field :source_generation_franchise, :integer
    field :source_generation_branch, :integer
    timestamps(type: :utc_datetime)
  end
end
