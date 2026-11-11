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
      <button type="button" id="intake-menu" popovertarget="intake-popover" class="btn">
        <.icon name="hero-adjustments-horizontal" class="size-5" /> {gettext("Order intake")}
      </button>
      <div
        id="intake-popover"
        popover="auto"
        phx-hook=".IntakePopover"
        class="fixed inset-auto m-0 w-80 max-w-[calc(100vw-1rem)] space-y-4 overflow-y-auto rounded-box border border-base-300 bg-base-100 p-4 shadow"
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
    <script :type={Phoenix.LiveView.ColocatedHook} name=".IntakePopover">
      export default {
        mounted() {
          this.position = () => {
            if (!this.el.matches(':popover-open')) return
            const trigger = document.getElementById('intake-menu')
            if (!trigger) return

            const gap = 8
            const triggerRect = trigger.getBoundingClientRect()
            const width = this.el.getBoundingClientRect().width
            const below = window.innerHeight - triggerRect.bottom - gap * 2
            const above = triggerRect.top - gap * 2
            const opensAbove = below < this.el.scrollHeight && above > below
            const available = Math.max(0, opensAbove ? above : below)
            this.el.style.maxHeight = `${available}px`

            const height = this.el.getBoundingClientRect().height
            const left = Math.max(gap, Math.min(triggerRect.right - width, window.innerWidth - width - gap))
            const top = opensAbove
              ? Math.max(gap, triggerRect.top - height - gap)
              : Math.min(triggerRect.bottom + gap, window.innerHeight - height - gap)
            this.el.style.left = `${left}px`
            this.el.style.top = `${top}px`
          }
          this.onToggle = (event) => {
            if (event.newState === 'open') this.position()
          }
          this.onKeyDown = (event) => {
            if (event.key !== 'Escape' || !this.el.matches(':popover-open')) return
            event.preventDefault()
            event.stopPropagation()
            this.el.hidePopover()
            document.getElementById('intake-menu')?.focus()
          }
          this.el.addEventListener('toggle', this.onToggle)
          document.addEventListener('keydown', this.onKeyDown, true)
          window.addEventListener('resize', this.position)
          document.addEventListener('scroll', this.position, true)
        },
        updated() { this.position() },
        destroyed() {
          this.el.removeEventListener('toggle', this.onToggle)
          document.removeEventListener('keydown', this.onKeyDown, true)
          window.removeEventListener('resize', this.position)
          document.removeEventListener('scroll', this.position, true)
        },
      }
    </script>
    """
  end

  defp time(nil, _branch_id), do: ""
  defp time(at, branch_id), do: Calendar.strftime(LocalTime.local(at, branch_id), "%H:%M")
end
