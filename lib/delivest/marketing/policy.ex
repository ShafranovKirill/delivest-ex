defmodule Delivest.Marketing.Policy do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "marketing_policies" do
    field :name, :string
    field :scope, Ecto.Enum, values: [:franchise, :branches]
    field :reward_branch_id, :binary_id
    field :bonus_amount, :integer
    field :inactivity_days, :integer
    field :reward_ttl_days, :integer
    field :attribution_days, :integer, default: 7
    field :initial_mode, Ecto.Enum, values: [:all_current, :future_only], default: :future_only
    field :activated_at, :utc_datetime
    field :baseline_snapshot_id, :binary_id
    field :baseline_complete, :boolean, default: false
    field :evaluated_run_id, :binary_id
    field :status, Ecto.Enum, values: [:draft, :initializing, :active, :paused], default: :draft
    field :channels, {:array, :string}, default: ["in_app"]
    field :message_title, :string
    field :message_body, :string
    field :max_issues, :integer
    field :issued_count, :integer, default: 0
    field :last_error, :string
    field :revision, :integer, default: 1
    field :cursor_client_id, :binary_id
    field :deleted_at, :utc_datetime
    belongs_to :segment, Delivest.Segments.Segment
    belongs_to :promotion, Delivest.Promo.Promotion
    many_to_many :branches, Delivest.Identity.Branch, join_through: "marketing_policy_branches"
    timestamps(type: :utc_datetime)
  end

  def changeset(policy, attrs) do
    policy
    |> cast(attrs, [
      :name,
      :scope,
      :segment_id,
      :reward_branch_id,
      :promotion_id,
      :bonus_amount,
      :inactivity_days,
      :reward_ttl_days,
      :attribution_days,
      :initial_mode,
      :channels,
      :message_title,
      :message_body,
      :max_issues
    ])
    |> validate_required([
      :name,
      :scope,
      :segment_id,
      :reward_branch_id,
      :inactivity_days,
      :reward_ttl_days,
      :attribution_days,
      :initial_mode,
      :channels,
      :message_title,
      :message_body
    ])
    |> validate_length(:name, min: 2, max: 120)
    |> validate_length(:message_title, min: 1, max: 120)
    |> validate_length(:message_body, min: 1, max: 500)
    |> validate_number(:inactivity_days, greater_than: 0)
    |> validate_number(:reward_ttl_days, greater_than: 0)
    |> validate_number(:attribution_days, greater_than: 0)
    |> validate_number(:max_issues, greater_than: 0)
    |> validate_number(:bonus_amount, greater_than: 0)
    |> validate_change(:channels, fn _, channels ->
      if channels != [] and Enum.all?(channels, &(&1 in ~w(in_app push sms))),
        do: [],
        else: [channels: "invalid channels"]
    end)
    |> validate_reward()
  end

  defp validate_reward(changeset) do
    case {get_field(changeset, :promotion_id), get_field(changeset, :bonus_amount)} do
      {nil, nil} -> add_error(changeset, :promotion_id, "select a reward")
      {nil, _} -> changeset
      {_, nil} -> changeset
      {_, _} -> add_error(changeset, :promotion_id, "choose one reward")
    end
  end
end
