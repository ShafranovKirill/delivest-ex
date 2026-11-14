defmodule DelivestWeb.Staff.BranchLive.WorkingHoursComponent do
  use DelivestWeb, :live_component

  defp weekdays do
    [
      {:monday, gettext("Monday")},
      {:tuesday, gettext("Tuesday")},
      {:wednesday, gettext("Wednesday")},
      {:thursday, gettext("Thursday")},
      {:friday, gettext("Friday")},
      {:saturday, gettext("Saturday")},
      {:sunday, gettext("Sunday")}
    ]
  end

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(:working_hours, assigns.working_hours || %{})
     |> assign(:days, weekdays())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-3">
      <p class="text-sm text-base-content/70">
        {gettext("Set the usual opening hours for each day of the week.")}
      </p>
      <%= for {day_key, day_label} <- @days do %>
        <% day_key_str = Atom.to_string(day_key) %>
        <% schedule = Map.get(@working_hours, day_key) || Map.get(@working_hours, day_key_str) || %{} %>

        <% enabled = Map.get(schedule, :enabled) || Map.get(schedule, "enabled") || false %>
        <% open_at = Map.get(schedule, :open) || Map.get(schedule, "open") || "" %>
        <% close_at = Map.get(schedule, :close) || Map.get(schedule, "close") || "" %>
        <div class="grid grid-cols-2 gap-2 items-center rounded-box bg-base-200/40 px-2 py-2 sm:grid-cols-[110px_minmax(0,1fr)_minmax(0,1fr)_auto]">
          <div class="text-xs font-semibold uppercase text-base-content/70">{day_label}</div>

          <label class={[
            "row-start-2 flex flex-col gap-1 text-[11px] uppercase text-base-content/60 sm:row-auto",
            !enabled && "opacity-40"
          ]}>
            <span>{gettext("Open")}</span>
            <input
              type="time"
              name={"branch_form[working_hours][#{day_key}][open]"}
              value={open_at}
              class="input input-bordered input-xs w-full"
            />
          </label>

          <label class={[
            "row-start-2 flex flex-col gap-1 text-[11px] uppercase text-base-content/60 sm:row-auto",
            !enabled && "opacity-40"
          ]}>
            <span>{gettext("Close")}</span>
            <input
              type="time"
              name={"branch_form[working_hours][#{day_key}][close]"}
              value={close_at}
              class="input input-bordered input-xs w-full"
            />
          </label>

          <label class="col-start-2 row-start-1 flex items-center justify-end gap-2 text-[11px] uppercase text-base-content/60 h-full sm:col-auto sm:row-auto sm:justify-center">
            <input
              type="hidden"
              name={"branch_form[working_hours][#{day_key}][enabled]"}
              value="false"
            />
            <input
              type="checkbox"
              name={"branch_form[working_hours][#{day_key}][enabled]"}
              value="true"
              checked={enabled}
              class="checkbox checkbox-xs"
            />
            <span>{if enabled, do: gettext("Working day"), else: gettext("Day off")}</span>
          </label>
        </div>
      <% end %>
    </div>
    """
  end
end
