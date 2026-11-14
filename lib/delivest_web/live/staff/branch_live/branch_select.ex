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

    intent =
      if params["modal"] == "true",
        do: StaffBranchPath.selection_intent(params["from"], params["return_to"]),
        else: :error

    {modal?, from, return_to} =
      case intent do
        {:ok, %{source: source, return_to: return_to}} -> {true, source, return_to}
        :error -> {false, nil, "/staff/dashboard"}
      end

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
       to: if(modal?, do: nil, else: to),
       modal?: modal?,
       from: from,
       return_to: return_to
     )}
  end

  def staff_page_header(%{modal?: true} = assigns) do
    ~H"""
    <div class="sr-only" aria-hidden="true"></div>
    """
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
  def handle_event("close_branch_selector", _params, socket) do
    {:noreply, push_navigate(socket, to: socket.assigns.return_to)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      :if={@modal?}
      id="branch-select-dialog"
      role="dialog"
      aria-modal="true"
      aria-labelledby="branch-select-dialog-title"
      phx-hook="FoundationDialog"
      data-dirty="false"
      data-close-event="close_branch_selector"
      class="fixed inset-0 z-[60] grid place-items-center p-4"
    >
      <div class="absolute inset-0 bg-black/50" phx-click="close_branch_selector" aria-hidden="true">
      </div>
      <div class="relative flex max-h-[calc(100dvh-2rem)] w-full max-w-lg flex-col rounded-box bg-base-100 shadow-xl">
        <div class="flex items-center justify-between border-b border-base-300 p-4">
          <h2 id="branch-select-dialog-title" class="text-lg font-semibold">
            {gettext("Select a branch")}
          </h2>
          <button
            type="button"
            phx-click="close_branch_selector"
            aria-label={gettext("Close")}
            class="btn btn-ghost btn-square"
          >×</button>
        </div>
        <div class="min-h-0 overflow-y-auto p-4">
          <.branch_choices
            entries={@entries}
            kitchen_only?={@kitchen_only?}
            available?={@available?}
            to={@to}
            from={@from}
          />
        </div>
      </div>
    </div>
    <.branch_choices
      :if={!@modal?}
      entries={@entries}
      kitchen_only?={@kitchen_only?}
      available?={@available?}
      to={@to}
      from={@from}
    />
    """
  end

  attr :entries, :list, required: true
  attr :kitchen_only?, :boolean, required: true
  attr :available?, :boolean, required: true
  attr :to, :string, default: nil
  attr :from, :string, default: nil

  defp branch_choices(assigns) do
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
              href={select_path(branch, @to, @from)}
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

  defp select_path(branch, _to, from) when is_binary(from),
    do: ~p"/staff/branches/select/#{branch.id}?#{%{from: from, selection: true}}"

  defp select_path(branch, nil, nil), do: ~p"/staff/branches/select/#{branch.id}"
  defp select_path(branch, to, nil), do: ~p"/staff/branches/select/#{branch.id}?#{%{to: to}}"
end
