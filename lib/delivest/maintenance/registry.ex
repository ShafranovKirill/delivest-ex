defmodule Delivest.Maintenance.Registry do
  @moduledoc "Whitelisted daily maintenance tasks and their scope."

  import Ecto.Query

  alias Delivest.Identity.Branch
  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Repo

  @global [
    %{
      key: "cart_cleanup",
      worker: Delivest.Oms.Workers.CartCleanupWorker,
      scope: :global,
      hour: 3,
      max_attempts: 3
    },
    %{
      key: "loyalty_expire",
      worker: Delivest.Loyalty.ExpireWorker,
      scope: :global,
      hour: 3,
      max_attempts: 3
    },
    %{
      key: "logs_prune",
      worker: Delivest.Logs.PruneWorker,
      scope: :global,
      hour: 3,
      max_attempts: 3
    },
    %{
      key: "thumbnail_backfill",
      worker: Delivest.Media.Workers.ThumbnailBackfillWorker,
      scope: :global,
      hour: 3,
      max_attempts: 1
    }
  ]

  @max_timeout_ms :timer.minutes(90)

  def max_timeout_ms, do: @max_timeout_ms

  def timeout_ms(task), do: Map.get(task, :timeout_ms, @max_timeout_ms)
  def max_attempts(task), do: Map.get(task, :max_attempts, 3)

  def validate(task) do
    timeout = timeout_ms(task)
    attempts = max_attempts(task)

    if is_integer(timeout) and timeout > 0 and timeout <= @max_timeout_ms and
         is_integer(attempts) and attempts > 0,
       do: :ok,
       else: {:error, :invalid_timeout}
  end

  def tasks, do: Application.get_env(:delivest, __MODULE__, @global)

  def task(key), do: Enum.find(tasks(), &(&1.key == key))

  def scopes(%{scope: :global} = task),
    do: [{task, "global", "global", Delivest.LocalTime.timezone()}]

  def scopes(%{scope: :branch} = task) do
    from(b in Branch,
      left_join: i in BranchInfo,
      on: i.branch_id == b.id,
      where: is_nil(b.deleted_at),
      select: {b.id, i.timezone}
    )
    |> Repo.all()
    |> Enum.map(fn {id, timezone} ->
      {task, "branch", id, timezone || Delivest.LocalTime.timezone()}
    end)
  end

  def resolve(key, scope_type) do
    case task(key) do
      %{scope: :global} = task when scope_type == "global" -> validated(task)
      %{scope: :branch} = task when scope_type == "branch" -> validated(task)
      _ -> {:error, :unknown_task}
    end
  end

  defp validated(task) do
    case validate(task) do
      :ok -> {:ok, task}
      error -> error
    end
  end
end
