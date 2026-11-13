defmodule DelivestWeb.Staff.BranchLive.BranchSelect do
  use DelivestWeb, :live_view

  alias Delivest.Identity
  alias Delivest.Oms.Kitchen

  alias DelivestWeb.{KitchenAccess, StaffBranchPath}

  @impl true
  def mount(params, _session, socket) do
    staff = socket.assigns[:current_staff]
    to = if StaffBranchPath.valid_section?(params["to"]), do: params["to"]
    kitchen_only? = Kitchen.account?(staff)

    entries =
      staff
      |> Identity.list_branch_for_staff(preload: :info)
      |> Enum.map(fn branch ->
        %{
          branch: branch,
          kitchen?: not kitchen_only? or KitchenAccess.available?(staff, branch)
        }
      end)

    {:ok,
     assign(socket,
       entries: entries,
       page_title: gettext("Select a branch"),
       kitchen_only?: kitchen_only?,
       available?: Enum.any?(entries, & &1.kitchen?),
       to: to
     )}
  end

  def staff_page_header(assigns) do
    ~H"""
    <.page_header
      title={gettext("Select a branch")}
      subtitle={gettext("Choose a branch to continue working in the system")}
    />
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div :if={@kitchen_only?} id="branch-select-kitchen-note" class="alert alert-info mb-4">
        <.icon name="hero-information-circle" class="size-5" />
        <span>
          {gettext(
            "You work in the kitchen. A branch opens only when its kitchen is on and works in the app."
          )}
        </span>
      </div>

      <div class="space-y-4">
        <%= for %{branch: branch, kitchen?: kitchen?} <- @entries do %>
          <%= if kitchen? do %>
            <.link
              href={select_path(branch, @to)}
              method="get"
              class="block p-6 rounded-box border border-base-300 bg-base-100 shadow-sm hover:border-base-content/30 hover:shadow-md transition-all group"
            >
              <h2 class="text-lg font-semibold tracking-tight text-base-content group-hover:text-primary transition-colors">
                {branch.name}
              </h2>
              <p class="mt-1 text-sm text-base-content/60">
                {gettext("Click to activate this branch")}
              </p>
            </.link>
          <% else %>
            <div
              id={"branch-select-disabled-#{branch.id}"}
              class="block p-6 rounded-box border border-dashed border-base-300 bg-base-200/40"
            >
              <h2 class="text-lg font-semibold tracking-tight text-base-content/60">
                {branch.name}
              </h2>
              <p class="mt-1 text-sm text-error">
                {KitchenAccess.message(branch)}
              </p>
            </div>
          <% end %>
        <% end %>
      </div>

      <div
        :if={@entries == []}
        class="mt-6 p-6 rounded-box border border-base-300 bg-base-100 shadow-sm"
      >
        <p class="text-sm text-base-content/70">
          {gettext(
            "You do not have access to any active branches. Please contact your system administrator."
          )}
        </p>
      </div>

      <div
        :if={@kitchen_only? and not @available?}
        id="branch-select-no-kitchen"
        class="mt-6 space-y-4 rounded-box border border-base-300 bg-base-100 p-6 shadow-sm"
      >
        <p class="text-sm text-base-content/70">
          {gettext(
            "None of your branches has a kitchen available in the app. Please contact your system administrator or log out."
          )}
        </p>
        <.link href={~p"/staff/auth/log_out"} method="delete" class="btn btn-outline">
          {gettext("Log out")}
        </.link>
      </div>
    </div>
    """
  end

  defp select_path(branch, nil), do: ~p"/staff/branches/select/#{branch.id}"
  defp select_path(branch, to), do: ~p"/staff/branches/select/#{branch.id}?#{%{to: to}}"
end
