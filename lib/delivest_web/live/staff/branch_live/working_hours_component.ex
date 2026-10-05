defmodule DelivestWeb.Staff.BranchLive.WorkingHoursComponent do
  use DelivestWeb, :live_component

  defp weekdays do
    [
      {:monday, gettext("Mon")},
      {:tuesday, gettext("Tue")},
      {:wednesday, gettext("Wed")},
      {:thursday, gettext("Thu")},
      {:friday, gettext("Fri")},
      {:saturday, gettext("Sat")},
      {:sunday, gettext("Sun")}
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
    <div class="p-4 pt-0 space-y-3 border-t border-base-200">
      <%= for {day_key, day_label} <- @days do %>
        <% day_key_str = Atom.to_string(day_key) %>
        <% schedule = Map.get(@working_hours, day_key) || Map.get(@working_hours, day_key_str) || %{} %>

        <% enabled = Map.get(schedule, :enabled) || Map.get(schedule, "enabled") || false %>
        <% open_at = Map.get(schedule, :open) || Map.get(schedule, "open") || "" %>
        <% close_at = Map.get(schedule, :close) || Map.get(schedule, "close") || "" %>
        <div class="grid grid-cols-[72px_minmax(0,1fr)_minmax(0,1fr)_auto] gap-2 items-center rounded-box bg-base-200/40 px-2 py-2">
          <div class="text-xs font-semibold uppercase text-base-content/70">{day_label}</div>

          <label class="flex flex-col gap-1 text-[11px] uppercase text-base-content/60">
            <span>{gettext("Open")}</span>
            <input
              type="time"
              name={"branch_form[working_hours][#{day_key}][open]"}
              value={open_at}
              class="input input-bordered input-xs w-full"
            />
          </label>

          <label class="flex flex-col gap-1 text-[11px] uppercase text-base-content/60">
            <span>{gettext("Close")}</span>
            <input
              type="time"
              name={"branch_form[working_hours][#{day_key}][close]"}
              value={close_at}
              class="input input-bordered input-xs w-full"
            />
          </label>

          <label class="flex items-center justify-center gap-2 text-[11px] uppercase text-base-content/60 h-full">
            <input
              type="checkbox"
              name={"branch_form[working_hours][#{day_key}][enabled]"}
              value="true"
              checked={enabled}
              class="checkbox checkbox-xs"
            />
            <span>{gettext("On")}</span>
          </label>
        </div>
      <% end %>
    </div>
    """
  end
end
