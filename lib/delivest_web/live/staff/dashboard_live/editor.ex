defmodule DelivestWeb.Staff.DashboardLive.Editor do
  use DelivestWeb, :html

  attr :layout, :map, required: true
  attr :allowed_widgets, :list, required: true
  attr :allowed_actions, :list, required: true
  attr :widget_titles, :map, required: true
  attr :action_titles, :map, required: true

  def catalog(assigns) do
    visible = MapSet.new(Enum.map(assigns.layout.widgets, & &1.id))
    assigns = assign(assigns, :visible, visible)

    ~H"""
    <aside
      id="dashboard-catalog"
      class="dashboard-editor-panel rounded-box border border-base-300 bg-base-100 p-4"
    >
      <div class="mb-4">
        <h2 class="text-lg font-semibold">{gettext("Widgets")}</h2>
        <p class="mt-1 text-sm text-base-content/65">
          {gettext("Drag a card by its handle. Resize it from the lower corner.")}
        </p>
        <p class="mt-1 text-sm text-base-content/65 dashboard-editor-touch-hint">
          {gettext("Use the arrows on cards to change their order.")}
        </p>
        <p class="mt-2 text-xs text-base-content/60">
          {gettext("This layout is shared across all branches. Changes take effect after you save.")}
        </p>
      </div>
      <div class="space-y-4">
        <section aria-label={gettext("Visible widgets")}>
          <h3 class="mb-2 text-xs font-semibold uppercase tracking-wide text-base-content/60">
            {gettext("Visible widgets")}
          </h3>
          <div class="dashboard-editor-list">
            <%= for id <- @allowed_widgets, MapSet.member?(@visible, id) do %>
              <div class="dashboard-editor-row">
                <span
                  id={"dashboard-catalog-title-#{id}"}
                  class="min-w-0 truncate text-sm font-medium"
                >{Gettext.gettext(DelivestWeb.Gettext, Map.fetch!(@widget_titles, id))}</span>
                <button
                  id={"dashboard-hide-#{id}"}
                  type="button"
                  phx-click="dashboard_remove"
                  phx-value-id={id}
                  class="btn btn-xs btn-ghost"
                  aria-describedby={"dashboard-catalog-title-#{id}"}
                >
                  <.icon name="hero-eye-slash" class="size-4" />{gettext("Hide")}
                </button>
              </div>
            <% end %>
            <p
              :if={MapSet.disjoint?(@visible, MapSet.new(@allowed_widgets))}
              class="px-3 py-2 text-sm text-base-content/60"
            >
              {gettext("No visible widgets")}
            </p>
          </div>
        </section>
        <section aria-label={gettext("Hidden widgets")}>
          <h3 class="mb-2 text-xs font-semibold uppercase tracking-wide text-base-content/60">
            {gettext("Hidden widgets")}
          </h3>
          <div class="dashboard-editor-list">
            <%= for id <- @allowed_widgets, not MapSet.member?(@visible, id) do %>
              <div class="dashboard-editor-row">
                <span
                  id={"dashboard-catalog-title-#{id}"}
                  class="min-w-0 truncate text-sm text-base-content/70"
                >{Gettext.gettext(DelivestWeb.Gettext, Map.fetch!(@widget_titles, id))}</span>
                <button
                  id={"dashboard-add-#{id}"}
                  type="button"
                  phx-click="dashboard_add"
                  phx-value-id={id}
                  class="btn btn-xs btn-outline"
                  aria-describedby={"dashboard-catalog-title-#{id}"}
                >
                  <.icon name="hero-plus" class="size-4" />{gettext("Show")}
                </button>
              </div>
            <% end %>
            <p
              :if={Enum.all?(@allowed_widgets, &MapSet.member?(@visible, &1))}
              class="px-3 py-2 text-sm text-base-content/60"
            >
              {gettext("All widgets are visible")}
            </p>
          </div>
        </section>
        <section
          :if={@allowed_actions != []}
          id="dashboard-actions-settings"
          class="border-t border-base-200 pt-4"
        >
          <h3 class="text-sm font-semibold">{gettext("Quick actions")}</h3>
          <p class="mb-3 mt-1 text-xs text-base-content/60">
            {gettext("Choose which shortcuts appear on the overview.")}
          </p>
          <div class="flex flex-wrap gap-2">
            <button
              :for={id <- @allowed_actions}
              id={"dashboard-action-#{id}"}
              type="button"
              phx-click="dashboard_action"
              phx-value-id={id}
              aria-pressed={to_string(id in @layout.actions)}
              class={["btn btn-xs", if(id in @layout.actions, do: "btn-primary", else: "btn-outline")]}
            >
              <.icon name={elem(Map.fetch!(@action_titles, id), 1)} class="size-4" />
              {Gettext.gettext(DelivestWeb.Gettext, elem(Map.fetch!(@action_titles, id), 0))}
            </button>
          </div>
        </section>
      </div>
    </aside>
    """
  end

  attr :item, :map, required: true
  attr :title, :string, required: true

  def widget_controls(assigns) do
    ~H"""
    <div class="dashboard-widget-controls">
      <span
        class="dashboard-drag-handle"
        role="img"
        aria-label={gettext("Drag widget")}
        title={gettext("Drag widget")}
      >⠿</span>
      <span class="min-w-0 flex-1 truncate text-xs font-semibold">{@title}</span>
      <button
        id={"dashboard-move-up-#{@item.id}"}
        type="button"
        phx-click="dashboard_move"
        phx-value-id={@item.id}
        phx-value-direction="up"
        aria-label={gettext("Move up")}
        class="btn btn-xs btn-ghost dashboard-mobile-move"
      ><.icon name="hero-arrow-up" class="size-4" /></button>
      <button
        id={"dashboard-move-down-#{@item.id}"}
        type="button"
        phx-click="dashboard_move"
        phx-value-id={@item.id}
        phx-value-direction="down"
        aria-label={gettext("Move down")}
        class="btn btn-xs btn-ghost dashboard-mobile-move"
      ><.icon name="hero-arrow-down" class="size-4" /></button>
      <button
        id={"dashboard-remove-#{@item.id}"}
        type="button"
        phx-click="dashboard_remove"
        phx-value-id={@item.id}
        aria-label={gettext("Hide widget")}
        class="btn btn-xs btn-ghost"
      ><.icon name="hero-x-mark" class="size-4" /></button>
    </div>
    """
  end
end
