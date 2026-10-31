defmodule DelivestWeb.Staff.IntegrationLive.YandexEdaBusy do
  use DelivestWeb, :html

  alias Delivest.LocalTime

  attr :busy, :any, default: nil
  attr :branch_id, :string, required: true

  def plate(%{busy: nil} = assigns), do: ~H""

  def plate(assigns) do
    ~H"""
    <div id="yandex-eda-busy" role="alert" class="alert alert-warning">
      <.icon name="hero-clock" class="size-5" />
      <span>
        {gettext("Yandex Eda high demand: +%{minutes} min until %{time}",
          minutes: @busy.extra_minutes,
          time: Calendar.strftime(LocalTime.local(@busy.valid_till, @branch_id), "%H:%M")
        )}
      </span>
    </div>
    """
  end
end
