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
    <div>
      <button
        type="button"
        id="intake-menu"
        aria-haspopup="dialog"
        phx-click={JS.dispatch("delivest:show-intake", to: "#intake-dialog")}
        class="btn btn-sm"
      >
        <.icon name="hero-adjustments-horizontal" class="size-5" /> {gettext("Order intake")}
      </button>
      <dialog
        id="intake-dialog"
        class="modal"
        aria-labelledby="intake-dialog-title"
        phx-mounted={JS.ignore_attributes("open")}
      >
        <div class="modal-box max-h-[calc(100dvh-2rem)] max-w-lg overflow-y-auto space-y-4 whitespace-normal">
          <div class="flex items-center justify-between gap-3">
            <h2 id="intake-dialog-title" class="text-lg font-semibold">{gettext("Order intake")}</h2>
            <button
              id="intake-close"
              type="button"
              class="btn btn-ghost btn-square btn-sm"
              aria-label={gettext("Close")}
              autofocus
              phx-click={close_intake()}
            >
              <.icon name="hero-x-mark" class="size-5" />
            </button>
          </div>
          <form
            id="intake-pause-form"
            phx-submit={close_intake(JS.push("intake_pause"))}
            class="grid gap-2"
          >
            <label class="grid gap-1 text-sm">
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
          <form
            id="intake-load-form"
            phx-submit={close_intake(JS.push("intake_load"))}
            class="grid gap-2"
          >
            <label class="grid gap-1 text-sm">
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
        <button
          type="button"
          class="modal-backdrop"
          aria-label={gettext("Close")}
          phx-click={close_intake()}
        ></button>
      </dialog>
    </div>
    """
  end

  defp close_intake(js \\ %JS{}),
    do:
      js
      |> JS.dispatch("delivest:close-intake", to: "#intake-dialog")
      |> JS.focus(to: "#intake-menu")

  defp time(nil, _branch_id), do: ""
  defp time(at, branch_id), do: Calendar.strftime(LocalTime.local(at, branch_id), "%H:%M")
end
