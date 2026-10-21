defmodule DelivestWeb.Staff.LogLive.Components.TabsComponent do
  use DelivestWeb, :html

  attr :active, :atom, required: true

  def render_tabs(assigns) do
    assigns =
      assign(assigns, :tabs, [
        {:events, ~p"/staff/logs", "hero-clock", gettext("Events")},
        {:raw, ~p"/staff/logs/raw", "hero-command-line", gettext("Raw logs")},
        {:errors, ~p"/staff/logs/errors", "hero-exclamation-triangle", gettext("Errors")},
        {:hints, ~p"/staff/logs/hints", "hero-light-bulb", gettext("Hints")}
      ])

    ~H"""
    <div role="tablist" class="tabs tabs-boxed w-fit max-w-full overflow-x-auto">
      <.link
        :for={{tab, path, icon, label} <- @tabs}
        patch={path}
        role="tab"
        class={["tab gap-2 whitespace-nowrap", @active == tab && "tab-active font-bold"]}
      >
        <.icon name={icon} class="size-4" />
        {label}
      </.link>
    </div>
    """
  end
end
