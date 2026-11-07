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
    pause(staff, branch, duration, reason, true)
  end

  defp pause(staff, branch, duration, reason, notify?) do
    until = pause_until(duration, branch.id)

    update(
      staff,
      branch,
      "intake.paused",
      %{
        paused_until: until,
        pause_reason: blank_to_nil(reason)
      },
      notify?
    )
  end

  def start_load(staff, %Branch{} = branch, minutes, duration) when is_integer(minutes) do
    start_load(staff, branch, minutes, duration, true)
  end

  defp start_load(staff, branch, minutes, duration, notify?) do
    update(
      staff,
      branch,
      "intake.load_started",
      %{
        load_minutes: minutes,
        load_until: pause_until(duration, branch.id)
      },
      notify?
    )
  end

  def resume(staff, %Branch{} = branch) do
    update(staff, branch, "intake.resumed", %{
      paused_until: nil,
      pause_reason: nil,
      load_minutes: 0,
      load_until: nil
    })
  end

  @doc "Top-level bulk update; do not nest in another transaction because notification follows this commit."
  def pause_many(staff, %Branch{} = branch, selected_ids, duration, reason) do
    update_many(staff, branch, selected_ids, fn target ->
      pause(staff, target, duration, reason, false)
    end)
  end

  @doc "Top-level bulk update; do not nest in another transaction because notification follows this commit."
  def start_load_many(staff, %Branch{} = branch, selected_ids, minutes, duration) do
    update_many(staff, branch, selected_ids, fn target ->
      start_load(staff, target, minutes, duration, false)
    end)
  end

  defp update_many(staff, branch, selected_ids, action) when is_list(selected_ids) do
    staff = Repo.preload(staff, :branches)
    accessible = Identity.list_branch_for_staff(staff)
    ids = Enum.map(accessible, & &1.id)

    if branch.id in ids and Enum.all?(selected_ids, &(&1 in ids)) do
      targets = [
        branch | Enum.filter(accessible, &(&1.id in selected_ids and &1.id != branch.id))
      ]

      result =
        Repo.transaction(fn ->
          Enum.each(targets, fn target ->
            case action.(target) do
              {:ok, _} -> :ok
              {:error, reason} -> Repo.rollback(reason)
            end
          end)
        end)

      if match?({:ok, _}, result), do: Enum.each(targets, &notify_changed(&1.id))
      result
    else
      {:error, :forbidden}
    end
  end

  defp update_many(_staff, _branch, _selected_ids, _action), do: {:error, :forbidden}

  defp update(staff, branch, action, attrs, notify? \\ true) do
    with :ok <- Identity.authorize(staff, "orders.update", branch.id),
         %BranchInfo{} = info <- Repo.preload(branch, :info, force: true).info,
         {:ok, info} <- info |> change_intake(attrs) |> Repo.update() do
      if notify?, do: notify_changed(branch.id)

      Audit.record(staff, action, branch,
        metadata: Map.new(attrs, fn {k, v} -> {k, to_string(v)} end)
      )

      {:ok, status_of(info.intake, DateTime.utc_now())}
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  defp notify_changed(branch_id) do
    Cachex.del(:branch_cache, branch_id)
    Notifier.branch_changed(branch_id)
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
