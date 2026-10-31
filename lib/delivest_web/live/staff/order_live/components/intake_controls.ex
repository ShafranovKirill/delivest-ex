defmodule DelivestWeb.Staff.OrderLive.Components.IntakeControls do
  use DelivestWeb, :html

  alias Delivest.{Intake, LocalTime}

  attr :intake, :map, required: true
  attr :branch_id, :string, required: true
  attr :can_manage, :boolean, default: false

  def plate(%{intake: %{mode: :normal}} = assigns), do: ~H""

  def plate(assigns) do
    ~H"""
    <div
      id="intake-plate"
      role="alert"
      class={["alert", (@intake.mode == :paused && "alert-error") || "alert-warning"]}
    >
      <.icon name={(@intake.mode == :paused && "hero-pause-circle") || "hero-clock"} class="size-5" />
      <span :if={@intake.mode == :paused}>
        {gettext("Orders are paused until %{time}", time: time(@intake.until, @branch_id))}
        <span :if={@intake.reason}>· {@intake.reason}</span>
      </span>
      <span :if={@intake.mode == :load}>
        {gettext("High load: +%{minutes} min until %{time}",
          minutes: @intake.extra_minutes,
          time: time(@intake.until, @branch_id)
        )}
      </span>
      <button :if={@can_manage} id="intake-resume" phx-click="intake_resume" class="btn btn-sm">
        {gettext("Back to normal")}
      </button>
    </div>
    """
  end

  attr :can_manage, :boolean, default: false

  attr :branches, :list, default: []

  def menu(%{can_manage: false} = assigns), do: ~H""

  def menu(assigns) do
    ~H"""
    <div class="dropdown dropdown-end">
      <div tabindex="0" role="button" id="intake-menu" class="btn">
        <.icon name="hero-adjustments-horizontal" class="size-5" /> {gettext("Order intake")}
      </div>
      <div
        tabindex="0"
        class="dropdown-content z-10 mt-2 w-80 space-y-4 rounded-box border border-base-300 bg-base-100 p-4 shadow"
      >
        <form id="intake-pause-form" phx-submit="intake_pause" class="space-y-2">
          <label class="text-sm block">
            {gettext("Also apply to branches")}
            <select name="branches[]" multiple class="select select-sm w-full">
              <option :for={branch <- @branches} value={branch.id}>{branch.name}</option>
            </select>
          </label>
          <div class="font-semibold">{gettext("Pause")}</div>
          <select name="duration" class="select select-sm w-full">
            <option :for={minutes <- Intake.pause_minutes()} value={minutes}>
              {gettext("%{minutes} min", minutes: minutes)}
            </option>
            <option value="end_of_day">{gettext("Until the end of the day")}</option>
          </select>
          <input
            type="text"
            name="reason"
            maxlength="200"
            placeholder={gettext("Reason: no couriers, overload, breakdown")}
            class="input input-sm w-full"
          />
          <button type="submit" class="btn btn-sm btn-error w-full">
            {gettext("Stop taking orders")}
          </button>
        </form>
        <form id="intake-load-form" phx-submit="intake_load" class="space-y-2">
          <label class="text-sm block">
            {gettext("Also apply to branches")}
            <select name="branches[]" multiple class="select select-sm w-full">
              <option :for={branch <- @branches} value={branch.id}>{branch.name}</option>
            </select>
          </label>
          <div class="font-semibold">{gettext("High load")}</div>
          <select name="minutes" class="select select-sm w-full">
            <option :for={minutes <- Intake.load_minutes()} value={minutes}>
              +{gettext("%{minutes} min", minutes: minutes)}
            </option>
          </select>
          <select name="duration" class="select select-sm w-full">
            <option value="30">{gettext("for 30 min")}</option>
            <option value="60">{gettext("for 1 hour")}</option>
            <option value="end_of_day">{gettext("Until the end of the day")}</option>
          </select>
          <button type="submit" class="btn btn-sm btn-warning w-full">
            {gettext("Increase the time")}
          </button>
        </form>
      </div>
    </div>
    """
  end

  defp time(nil, _branch_id), do: ""
  defp time(at, branch_id), do: Calendar.strftime(LocalTime.local(at, branch_id), "%H:%M")
end
