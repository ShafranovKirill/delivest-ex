defmodule DelivestWeb.Staff.IntegrationLive.YandexEdaPause do
  use DelivestWeb, :html

  attr :pauses, Phoenix.LiveView.AsyncResult, required: true
  attr :can_edit, :boolean, required: true

  def pause(assigns) do
    ~H"""
    <section
      id="yandex-eda-pause"
      class="space-y-4 rounded-box border border-base-300 bg-base-100 p-5 sm:p-6"
    >
      <div>
        <h2 class="font-bold">{gettext("Pause in Yandex Eda")}</h2>
        <p class="text-sm text-base-content/60">
          {gettext("Yandex stops taking orders for the branch until the pause ends or is lifted.")}
        </p>
      </div>

      <.async_result :let={pauses} assign={@pauses}>
        <:loading>
          <p class="text-sm text-base-content/50">{gettext("Loading...")}</p>
        </:loading>
        <:failed>
          <p class="text-sm text-error">{gettext("Yandex did not return the pauses")}</p>
        </:failed>

        <p :if={pauses == []} class="text-sm text-base-content/50 italic">
          {gettext("No active pauses")}
        </p>

        <ul :if={pauses != []} class="divide-y divide-base-300">
          <li
            :for={pause <- pauses}
            id={"yandex-eda-pause-#{pause.id}"}
            class="flex items-center justify-between gap-3 py-2"
          >
            <div class="min-w-0 text-sm">
              <div class="font-medium">
                {period(pause)}
              </div>
              <div :if={pause.message || pause.source} class="truncate text-base-content/60">
                {Enum.reject([pause.source, pause.message], &is_nil/1) |> Enum.join(" · ")}
              </div>
            </div>
            <button
              :if={@can_edit and pause.cancelable}
              type="button"
              class="btn btn-sm"
              phx-click="resume"
              phx-value-id={pause.id}
            >
              {gettext("Lift")}
            </button>
          </li>
        </ul>
      </.async_result>

      <form
        :if={@can_edit}
        id="yandex-eda-pause-form"
        phx-submit="pause"
        class="grid gap-3 sm:grid-cols-[1fr_1fr_auto] sm:items-end"
      >
        <.input
          name="minutes"
          type="select"
          label={gettext("Duration")}
          value="30"
          options={duration_options()}
        />
        <.input
          name="tag"
          type="select"
          label={gettext("Reason")}
          value="too_busy"
          options={[
            {gettext("Too busy"), "too_busy"},
            {gettext("Technical problem"), "technical_problem"}
          ]}
        />
        <button type="submit" class="btn btn-warning" phx-disable-with={gettext("Saving...")}>
          <.icon name="hero-pause" class="size-4" />
          {gettext("Pause")}
        </button>
      </form>
    </section>
    """
  end

  defp duration_options do
    [
      {gettext("15 minutes"), "15"},
      {gettext("30 minutes"), "30"},
      {gettext("1 hour"), "60"},
      {gettext("2 hours"), "120"},
      {gettext("4 hours"), "240"},
      {gettext("Until lifted"), ""}
    ]
  end

  defp period(%{from: from, to: nil}), do: gettext("Since %{from}", from: time(from))

  defp period(%{from: from, to: to}),
    do: gettext("%{from} – %{to}", from: time(from), to: time(to))

  defp time(nil), do: "—"
  defp time(datetime), do: Calendar.strftime(datetime, "%d.%m %H:%M")
end
