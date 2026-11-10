defmodule Delivest.Repo.Migrations.MarketingPolicies do
  use Ecto.Migration

  def change do
    alter table(:promo_codes) do
      add :expires_at, :utc_datetime
    end

    create table(:marketing_policies, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :segment_id, references(:segments, type: :binary_id), null: false
      add :scope, :string, null: false
      add :reward_branch_id, references(:branches, type: :binary_id), null: false
      add :promotion_id, references(:promotions, type: :binary_id)
      add :bonus_amount, :integer
      add :inactivity_days, :integer, null: false
      add :reward_ttl_days, :integer, null: false
      add :attribution_days, :integer, null: false, default: 7
      add :initial_mode, :string, null: false, default: "future_only"
      add :activated_at, :utc_datetime
      add :baseline_snapshot_id, :binary_id
      add :baseline_complete, :boolean, null: false, default: false
      add :evaluated_run_id, :binary_id
      add :status, :string, null: false, default: "draft"
      add :channels, {:array, :string}, null: false, default: ["in_app"]
      add :message_title, :string, null: false
      add :message_body, :text, null: false
      add :max_issues, :integer
      add :issued_count, :integer, null: false, default: 0
      add :last_error, :string
      add :revision, :integer, null: false, default: 1
      add :cursor_client_id, :binary_id
      timestamps(type: :utc_datetime)
    end

    create constraint(:marketing_policies, :marketing_reward_xor,
             check: "(promotion_id IS NULL) <> (bonus_amount IS NULL)"
           )

    create constraint(:marketing_policies, :marketing_positive_values,
             check:
               "inactivity_days > 0 AND reward_ttl_days > 0 AND attribution_days > 0 AND (bonus_amount IS NULL OR bonus_amount > 0) AND (max_issues IS NULL OR max_issues > 0)"
           )

    create constraint(:marketing_policies, :marketing_status_check,
             check: "status IN ('draft', 'initializing', 'active', 'paused')"
           )

    create constraint(:marketing_policies, :marketing_scope_check,
             check: "scope IN ('franchise', 'branches')"
           )

    create constraint(:marketing_policies, :marketing_initial_mode_check,
             check: "initial_mode IN ('all_current', 'future_only')"
           )

    create index(:marketing_policies, [:status, :id])

    create table(:marketing_policy_branches, primary_key: false) do
      add :policy_id, references(:marketing_policies, type: :binary_id, on_delete: :delete_all),
        null: false

      add :branch_id, references(:branches, type: :binary_id), null: false
    end

    create unique_index(:marketing_policy_branches, [:policy_id, :branch_id])

    create table(:marketing_policy_excluded_clients, primary_key: false) do
      add :policy_id, references(:marketing_policies, type: :binary_id, on_delete: :delete_all),
        null: false

      add :client_id, references(:clients, type: :binary_id), null: false
    end

    create unique_index(:marketing_policy_excluded_clients, [:policy_id, :client_id])

    create table(:marketing_policy_excluded_segments, primary_key: false) do
      add :policy_id, references(:marketing_policies, type: :binary_id, on_delete: :delete_all),
        null: false

      add :segment_id, references(:segments, type: :binary_id), null: false
    end

    create unique_index(:marketing_policy_excluded_segments, [:policy_id, :segment_id])

    create table(:marketing_issues, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :policy_id, references(:marketing_policies, type: :binary_id), null: false
      add :client_id, references(:clients, type: :binary_id), null: false
      add :cycle_order_id, references(:orders, type: :binary_id), null: false
      add :branch_id, references(:branches, type: :binary_id), null: false
      add :reward_type, :string, null: false
      add :reward_id, :binary_id
      add :reward_amount, :integer
      add :issued_at, :utc_datetime, null: false
      add :expires_at, :utc_datetime, null: false
      add :attribution_until, :utc_datetime, null: false
      add :policy_revision, :integer, null: false
      add :source_generation_franchise, :bigint, null: false
      add :source_generation_branch, :bigint, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:marketing_issues, [:policy_id, :client_id, :cycle_order_id])
    create index(:marketing_issues, [:client_id, :issued_at])

    create table(:marketing_suppressions, primary_key: false) do
      add :policy_id, references(:marketing_policies, type: :binary_id), null: false
      add :client_id, references(:clients, type: :binary_id), null: false
      add :cycle_order_id, references(:orders, type: :binary_id), null: false
      add :reason, :string, null: false
      add :inserted_at, :utc_datetime, null: false
    end

    create unique_index(:marketing_suppressions, [:policy_id, :client_id, :cycle_order_id])

    create table(:marketing_baseline_members, primary_key: false) do
      add :policy_id, references(:marketing_policies, type: :binary_id, on_delete: :delete_all),
        null: false

      add :request_id, :binary_id, null: false
      add :client_id, references(:clients, type: :binary_id), null: false
      add :cycle_order_id, references(:orders, type: :binary_id), null: false
    end

    create unique_index(:marketing_baseline_members, [:policy_id, :request_id, :client_id],
             name: :marketing_baseline_request_member_idx
           )

    create table(:marketing_exclusions, primary_key: false) do
      add :policy_id, references(:marketing_policies, type: :binary_id), null: false
      add :client_id, references(:clients, type: :binary_id), null: false
      add :cycle_order_id, references(:orders, type: :binary_id), null: false
      add :reason, :string, null: false
      add :inserted_at, :utc_datetime, null: false
    end

    create unique_index(:marketing_exclusions, [:policy_id, :client_id, :cycle_order_id])

    create table(:marketing_evaluation_states, primary_key: false) do
      add :id, :integer, primary_key: true
      add :run_id, :binary_id
      add :last_policy_id, :binary_id
      add :started_at, :utc_datetime
    end

    create table(:segment_snapshot_leases, primary_key: false) do
      add :snapshot_id, :binary_id, null: false
      add :owner_type, :string, null: false
      add :owner_id, :binary_id, null: false
      add :inserted_at, :utc_datetime, null: false
    end

    create unique_index(:segment_snapshot_leases, [:owner_type, :owner_id])
    create index(:segment_snapshot_leases, [:snapshot_id])

    create table(:marketing_previews, primary_key: false) do
      add :policy_id, references(:marketing_policies, type: :binary_id, on_delete: :delete_all),
        primary_key: true

      add :policy_revision, :integer, null: false
      add :segment_revision, :integer, null: false
      add :feature_generation, :bigint, null: false
      add :segment_snapshot_id, :binary_id
      add :request_id, :binary_id, null: false
      add :status, :string, null: false
      add :cursor_client_id, :binary_id
      add :eligible_count, :integer, null: false, default: 0
      add :requested_at, :utc_datetime, null: false
      add :completed_at, :utc_datetime
    end

    create index(:marketing_previews, [:status, :requested_at])

    create table(:marketing_policy_audits, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :policy_id, references(:marketing_policies, type: :binary_id), null: false
      add :actor_id, :binary_id
      add :action, :string, null: false
      add :revision, :integer, null: false
      add :details, :map, null: false, default: %{}
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create table(:marketing_report_requests, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :policy_id, references(:marketing_policies, type: :binary_id, on_delete: :delete_all),
        null: false

      add :from_on, :date, null: false
      add :to_on, :date, null: false
      add :branch_key, :string, null: false, default: "all"
      add :status, :string, null: false, default: "pending"
      add :phase, :string, null: false, default: "issues"
      add :cursor_issued_at, :utc_datetime
      add :cursor_issue_id, :binary_id
      add :cursor_order_at, :utc_datetime
      add :cursor_order_id, :binary_id
      add :requested_at, :utc_datetime_usec, null: false
      add :as_of, :utc_datetime_usec
      add :data, :map
      add :updated_at, :utc_datetime_usec, null: false
    end

    create unique_index(:marketing_report_requests, [:policy_id, :from_on, :to_on, :branch_key],
             name: :marketing_report_request_scope_idx
           )

    create index(:marketing_report_requests, [:status, :requested_at],
             name: :marketing_report_pending_idx
           )

    create table(:marketing_report_links, primary_key: false) do
      add :request_id,
          references(:marketing_report_requests, type: :binary_id, on_delete: :delete_all),
          primary_key: true

      add :order_id, references(:orders, type: :binary_id), primary_key: true
      add :client_id, references(:clients, type: :binary_id), null: false
      add :branch_id, references(:branches, type: :binary_id), null: false
      add :issue_branch_id, references(:branches, type: :binary_id), null: false
      add :issue_day, :date, null: false
      add :net_revenue, :bigint, null: false
    end

    create index(:marketing_report_links, [:request_id, :issue_day, :issue_branch_id],
             name: :marketing_report_link_bucket_idx
           )

    create index(:marketing_report_links, [:order_id, :request_id],
             name: :marketing_report_link_order_idx
           )

    create table(:marketing_report_daily, primary_key: false) do
      add :request_id,
          references(:marketing_report_requests, type: :binary_id, on_delete: :delete_all),
          primary_key: true

      add :day, :date, primary_key: true
      add :branch_id, references(:branches, type: :binary_id), primary_key: true
      add :issued, :integer, null: false, default: 0
      add :bonus_points_issued, :bigint, null: false, default: 0
      add :in_app_available, :integer, null: false, default: 0
      add :push_provider_accepted, :integer, null: false, default: 0
      add :push_unknown, :integer, null: false, default: 0
      add :push_skipped, :integer, null: false, default: 0
      add :sms_unavailable, :integer, null: false, default: 0
      add :clicked_notices, :integer, null: false, default: 0
      add :linked_orders, :integer, null: false, default: 0
      add :linked_net_revenue, :bigint, null: false, default: 0
      add :promo_redemptions, :integer, null: false, default: 0
      add :recorded_promo_discount, :bigint, null: false, default: 0
    end

    create table(:marketing_report_comparisons, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :request_key, :string, null: false
      add :member_request_ids, {:array, :binary_id}, null: false
      add :member_as_of, :map, null: false
      add :status, :string, null: false, default: "pending"
      add :cursor_order_id, :binary_id
      add :requested_at, :utc_datetime_usec, null: false
      add :as_of, :utc_datetime_usec
      add :data, :map
      add :updated_at, :utc_datetime_usec, null: false
    end

    create unique_index(:marketing_report_comparisons, [:request_key])

    create index(:marketing_report_comparisons, [:status, :requested_at],
             name: :marketing_report_comparison_pending_idx
           )

    create table(:marketing_report_comparison_daily, primary_key: false) do
      add :comparison_id,
          references(:marketing_report_comparisons, type: :binary_id, on_delete: :delete_all),
          primary_key: true

      add :day, :date, primary_key: true
      add :branch_id, references(:branches, type: :binary_id), primary_key: true
      add :linked_orders, :integer, null: false, default: 0
      add :linked_net_revenue, :bigint, null: false, default: 0
    end

    create table(:marketing_report_comparison_clients, primary_key: false) do
      add :comparison_id,
          references(:marketing_report_comparisons, type: :binary_id, on_delete: :delete_all),
          primary_key: true

      add :client_id, references(:clients, type: :binary_id), primary_key: true
    end
  end
end
