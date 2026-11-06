defmodule Delivest.Repo.Migrations.AddCrmCommandReplay do
  use Ecto.Migration

  def up do
    alter table(:crm_command_deliveries) do
      add :args, :map
      add :execution_job_id, :bigint
    end

    execute """
      UPDATE crm_command_deliveries d
      SET args = j.args, execution_job_id = j.id
      FROM oban_jobs j WHERE j.id = d.job_id
    """
  end

  def down do
    alter table(:crm_command_deliveries) do
      remove :args
      remove :execution_job_id
    end
  end
end
