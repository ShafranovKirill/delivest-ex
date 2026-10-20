defmodule Delivest.Repo.Migrations.MoveCrmDataToJsonb do
  use Ecto.Migration

  def up do
    alter table(:branch_info) do
      add :crm, :map, null: false, default: %{}
    end

    alter table(:orders) do
      add :crm, :map
    end

    flush()

    execute """
    UPDATE branch_info
    SET crm = jsonb_build_object(
      'enabled', frontpad_enabled,
      'provider', CASE WHEN frontpad_enabled OR frontpad_api_key IS NOT NULL THEN 'frontpad' END,
      'frontpad', jsonb_strip_nulls(jsonb_build_object(
        'api_key', frontpad_api_key,
        'affiliate', frontpad_settings->>'frontpad_branch_id'
      ))
    )
    """

    execute """
    UPDATE orders
    SET crm = jsonb_strip_nulls(
      jsonb_build_object('provider', 'frontpad', 'external_id', crm_id) || COALESCE(crm_info, '{}'::jsonb)
    )
    WHERE crm_id IS NOT NULL OR crm_info IS NOT NULL OR status = 'crm'
    """

    execute """
    UPDATE oban_jobs
    SET worker = 'Delivest.Integrations.Crm.SyncWorker', queue = 'crm'
    WHERE worker = 'Delivest.Integrations.Frontpad.FrontpadWorker'
    """

    alter table(:branch_info) do
      remove :frontpad_api_key
      remove :frontpad_enabled
      remove :frontpad_settings
    end

    alter table(:orders) do
      remove :crm_id
      remove :crm_info
    end
  end

  def down do
    alter table(:branch_info) do
      add :frontpad_api_key, :string
      add :frontpad_enabled, :boolean, default: false, null: false
      add :frontpad_settings, :map, default: %{}
    end

    alter table(:orders) do
      add :crm_id, :string
      add :crm_info, :map
    end

    flush()

    execute """
    UPDATE branch_info
    SET frontpad_enabled = COALESCE((crm->>'enabled')::boolean AND crm->>'provider' = 'frontpad', false),
        frontpad_api_key = crm->'frontpad'->>'api_key',
        frontpad_settings = jsonb_strip_nulls(
          jsonb_build_object('frontpad_branch_id', crm->'frontpad'->>'affiliate')
        )
    """

    execute """
    UPDATE orders
    SET crm_id = crm->>'external_id',
        crm_info = crm - 'provider' - 'external_id'
    WHERE crm IS NOT NULL
    """

    execute """
    UPDATE oban_jobs
    SET worker = 'Delivest.Integrations.Frontpad.FrontpadWorker', queue = 'frontpad'
    WHERE worker = 'Delivest.Integrations.Crm.SyncWorker'
    """

    alter table(:branch_info) do
      remove :crm
    end

    alter table(:orders) do
      remove :crm
    end
  end
end
