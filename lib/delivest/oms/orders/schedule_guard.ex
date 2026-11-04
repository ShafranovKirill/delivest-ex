defmodule Delivest.Oms.Orders.ScheduleGuard do
  @moduledoc """
  Server-side check of a customer's requested preparation time.

  Staff, POS and external channel orders keep their own contracts; only the
  public storefront path is checked here. The schedule is read in the branch
  timezone and supports over-midnight windows and date exceptions.
  """

  alias Delivest.{Identity, Intake, LocalTime}
  alias Delivest.Identity.Branch.BranchInfo

  @days ~w(monday tuesday wednesday thursday friday saturday sunday)

  @spec check(term(), term(), keyword()) :: :ok | {:error, atom()}
  def check(branch_id, cook_by, opts \\ []) do
    if guarded?(opts) do
      do_check(branch_id, cook_by)
    else
      :ok
    end
  end

  defp guarded?(opts) do
    Keyword.get(opts, :source, "app") == "app" and
      is_nil(Keyword.get(opts, :channel)) and is_nil(Keyword.get(opts, :crm))
  end

  defp do_check(branch_id, cook_by) do
    case Identity.get_branch(branch_id, preload: [:info]) do
      {:ok, branch} ->
        case Intake.status(branch_id) do
          %{mode: :paused} = status -> {:error, {:branch_paused, status}}
          _ -> check_time(branch.info, branch_id, cook_by)
        end

      _ ->
        # The branch is validated by the cart and the public controller. A
        # missing record must not turn into a schedule error here.
        :ok
    end
  end

  defp check_time(info, branch_id, nil) do
    if open_at?(info, DateTime.utc_now(), branch_id),
      do: :ok,
      else: {:error, :branch_closed}
  end

  defp check_time(info, branch_id, cook_by) do
    case LocalTime.parse(cook_by, branch_id) do
      %DateTime{} = at ->
        cond do
          DateTime.compare(at, DateTime.utc_now()) != :gt -> {:error, :cook_by_in_past}
          open_at?(info, at, branch_id) -> :ok
          true -> {:error, :cook_by_outside_hours}
        end

      _ ->
        {:error, :cook_by_in_past}
    end
  end

  defp open_at?(nil, _at, _branch_id), do: true

  defp open_at?(%BranchInfo{} = info, at, branch_id) do
    hours = non_empty(info.working_hours)
    special = non_empty(info.special_hours)

    if is_nil(hours) and is_nil(special) do
      true
    else
      local = DateTime.shift_zone!(at, LocalTime.timezone(branch_id))
      date = DateTime.to_date(local)
      minutes = local.hour * 60 + local.minute

      [date, Date.add(date, -1)]
      |> Enum.any?(fn day ->
        window = work_window(day, hours, special)
        in_window?(window, minutes, day == date)
      end)
    end
  end

  defp non_empty(map) when is_map(map) and map_size(map) > 0, do: map
  defp non_empty(_map), do: nil

  defp work_window(day, hours, special) do
    exception = special && Map.get(special, Date.to_iso8601(day))
    schedule = exception || (hours && Map.get(hours, day_key(day)))

    cond do
      is_nil(schedule) and is_nil(hours) -> {0, 24 * 60}
      is_nil(schedule) -> nil
      not enabled?(schedule) -> nil
      true -> {clock(schedule["open"], 0), clock(schedule["close"], 24 * 60)}
    end
  end

  defp in_window?(nil, _minutes, _today?), do: false

  defp in_window?({open, close}, minutes, today?) do
    close = if close <= open, do: close + 24 * 60, else: close
    minutes = if today?, do: minutes, else: minutes + 24 * 60

    minutes >= open and minutes < close
  end

  defp clock(value, default) when is_binary(value) do
    case Regex.run(~r/^(\d{1,2}):(\d{2})/, value) do
      [_, hour, minute] -> String.to_integer(hour) * 60 + String.to_integer(minute)
      _ -> default
    end
  end

  defp clock(_value, default), do: default

  defp enabled?(%{"enabled" => value}), do: value in [true, "true"]
  defp enabled?(_schedule), do: false

  defp day_key(date), do: Enum.at(@days, Date.day_of_week(date) - 1)
end
