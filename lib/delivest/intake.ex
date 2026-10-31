defmodule Delivest.Intake do
  alias Delivest.{Audit, Identity, LocalTime, Repo}
  alias Delivest.Identity.Branch
  alias Delivest.Identity.Branch.{BranchInfo, IntakeSettings}
  alias Delivest.Oms.Orders.Notifier

  @pause_minutes [15, 30, 60]
  @load_minutes [10, 20, 30, 45, 60]

  def pause_minutes, do: @pause_minutes
  def load_minutes, do: @load_minutes

  def status(branch_id, now \\ DateTime.utc_now()) do
    case Identity.get_branch(branch_id, preload: :info) do
      {:ok, %{info: %BranchInfo{intake: %IntakeSettings{} = intake}}} -> status_of(intake, now)
      _ -> %{mode: :normal, extra_minutes: 0, until: nil, reason: nil}
    end
  end

  def accepting?(branch_id), do: status(branch_id).mode != :paused

  def extra_minutes(branch_id), do: status(branch_id).extra_minutes

  def status_of(%IntakeSettings{} = intake, now) do
    cond do
      active?(intake.paused_until, now) ->
        %{
          mode: :paused,
          extra_minutes: 0,
          until: intake.paused_until,
          reason: intake.pause_reason
        }

      active?(intake.load_until, now) and (intake.load_minutes || 0) > 0 ->
        %{mode: :load, extra_minutes: intake.load_minutes, until: intake.load_until, reason: nil}

      true ->
        %{mode: :normal, extra_minutes: 0, until: nil, reason: nil}
    end
  end

  def pause(staff, %Branch{} = branch, duration, reason \\ nil) do
    until = pause_until(duration, branch.id)

    update(staff, branch, "intake.paused", %{
      paused_until: until,
      pause_reason: blank_to_nil(reason)
    })
  end

  def start_load(staff, %Branch{} = branch, minutes, duration) when is_integer(minutes) do
    update(staff, branch, "intake.load_started", %{
      load_minutes: minutes,
      load_until: pause_until(duration, branch.id)
    })
  end

  def resume(staff, %Branch{} = branch) do
    update(staff, branch, "intake.resumed", %{
      paused_until: nil,
      pause_reason: nil,
      load_minutes: 0,
      load_until: nil
    })
  end

  defp update(staff, branch, action, attrs) do
    with :ok <- Identity.authorize(staff, "orders.update", branch.id),
         %BranchInfo{} = info <- Repo.preload(branch, :info, force: true).info,
         {:ok, info} <- info |> change_intake(attrs) |> Repo.update() do
      Cachex.del(:branch_cache, branch.id)
      Notifier.branch_changed(branch.id)

      Audit.record(staff, action, branch,
        metadata: Map.new(attrs, fn {k, v} -> {k, to_string(v)} end)
      )

      {:ok, status_of(info.intake, DateTime.utc_now())}
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  defp change_intake(info, attrs) do
    info
    |> Ecto.Changeset.cast(%{intake: attrs}, [])
    |> Ecto.Changeset.cast_embed(:intake, with: &IntakeSettings.changeset/2)
  end

  defp pause_until(:end_of_day, branch_id) do
    zone = LocalTime.timezone(branch_id)
    today = DateTime.utc_now() |> DateTime.shift_zone!(zone) |> DateTime.to_date()
    today |> LocalTime.end_of_day_utc(zone) |> DateTime.truncate(:second)
  end

  defp pause_until(minutes, _branch_id) when is_integer(minutes),
    do: DateTime.utc_now() |> DateTime.add(minutes, :minute) |> DateTime.truncate(:second)

  defp active?(%DateTime{} = until, now), do: DateTime.compare(until, now) == :gt
  defp active?(_until, _now), do: false

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: String.trim(value)
end
