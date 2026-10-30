defmodule DelivestWeb.Staff.BranchLive.SpecialHoursComponent do
  use DelivestWeb, :live_component

  alias Delivest.Identity

  @impl true
  def update(assigns, socket) do
    {:ok, socket |> assign(assigns) |> assign(:error, nil)}
  end

  @impl true
  def handle_event("add", %{"date" => date} = params, socket) do
    attrs = %{
      "enabled" => params["closed"] != "true",
      "open" => params["open"],
      "close" => params["close"]
    }

    with {:ok, date} <- Date.from_iso8601(date),
         {:ok, branch} <-
           Identity.set_special_day(socket.assigns.staff, socket.assigns.branch, date, attrs) do
      {:noreply, socket |> assign(branch: branch, error: nil)}
    else
      {:error, :forbidden} -> {:noreply, assign(socket, error: gettext("Permission denied"))}
      _ -> {:noreply, assign(socket, error: gettext("Check the date and the time"))}
    end
  end

  def handle_event("remove", %{"date" => date}, socket) do
    with {:ok, date} <- Date.from_iso8601(date),
         {:ok, branch} <-
           Identity.remove_special_day(socket.assigns.staff, socket.assigns.branch, date) do
      {:noreply, socket |> assign(branch: branch, error: nil)}
    else
      _ -> {:noreply, assign(socket, error: gettext("Permission denied"))}
    end
  end

  defp days(%{info: %{special_hours: hours}}) when is_map(hours),
    do: hours |> Enum.sort_by(&elem(&1, 0))

  defp days(_branch), do: []

  @impl true
  def render(assigns) do
    ~H"""
    <div id="special-hours" class="space-y-3 rounded-box border border-base-300 p-3">
      <div>
        <h3 class="font-semibold">{gettext("Special days")}</h3>
        <p class="text-sm text-base-content/60">
          {gettext("A holiday or a technical day replaces the weekly schedule for that date.")}
        </p>
      </div>

      <ul class="space-y-1">
        <li
          :for={{date, day} <- days(@branch)}
          id={"special-day-#{date}"}
          class="flex items-center justify-between gap-2 rounded-box bg-base-200/40 px-3 py-2 text-sm"
        >
          <span class="font-medium">{date}</span>
          <span :if={day["enabled"]}>{day["open"]}–{day["close"]}</span>
          <span :if={!day["enabled"]} class="text-error">{gettext("Closed")}</span>
          <button
            type="button"
            phx-click="remove"
            phx-value-date={date}
            phx-target={@myself}
            class="btn btn-ghost btn-xs"
          >
            {gettext("Remove")}
          </button>
        </li>
      </ul>

      <form
        id="special-hours-form"
        phx-submit="add"
        phx-target={@myself}
        class="grid grid-cols-2 items-end gap-2 sm:grid-cols-5"
      >
        <input type="date" name="date" required class="input input-bordered input-sm sm:col-span-2" />
        <input type="time" name="open" class="input input-bordered input-sm" />
        <input type="time" name="close" class="input input-bordered input-sm" />
        <label class="flex items-center gap-2 text-sm">
          <input type="checkbox" name="closed" value="true" class="checkbox checkbox-sm" />
          {gettext("Closed")}
        </label>
        <button type="submit" class="btn btn-sm btn-primary col-span-2 sm:col-span-5">
          {gettext("Add the day")}
        </button>
      </form>
      <p :if={@error} class="text-sm text-error">{@error}</p>
    </div>
    """
  end
end
