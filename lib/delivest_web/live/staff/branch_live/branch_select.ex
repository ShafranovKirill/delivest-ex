defmodule DelivestWeb.Staff.BranchLive.BranchSelect do
  use DelivestWeb, :live_view

  alias Delivest.{Couriers, Identity}
  alias Delivest.Oms.Kitchen

  alias DelivestWeb.{KitchenAccess, StaffBranchPath}

  @impl true
  def mount(params, _session, socket) do
    staff = socket.assigns[:current_staff]
    to = if StaffBranchPath.valid_section?(params["to"]), do: params["to"]
    kitchen_only? = Kitchen.account?(staff)

    intent = StaffBranchPath.selection_intent(params["from"], params["return_to"])

    {from, return_to} =
      case intent do
        {:ok, %{source: source, return_to: return_to}} -> {source, return_to}
        :error -> {nil, nil}
      end

    to = if(from, do: nil, else: to)

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
       to: to,
       from: from,
       return_to: return_to,
       network_path: if(entries == [], do: nil, else: network_choice_path(staff, from, to))
     )}
  end

  def staff_page_header(assigns) do
    ~H"""
    <.page_header
      title={gettext("Select a branch")}
      back={@return_to}
    />
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.branch_choices
      entries={@entries}
      kitchen_only?={@kitchen_only?}
      available?={@available?}
      to={@to}
      from={@from}
      network_path={@network_path}
    />
    """
  end

  attr :entries, :list, required: true
  attr :kitchen_only?, :boolean, required: true
  attr :available?, :boolean, required: true
  attr :to, :string, default: nil
  attr :from, :string, default: nil
  attr :network_path, :string, default: nil

  defp branch_choices(assigns) do
    ~H"""
    <div id="branch-select-page" class="space-y-6">
      <div :if={@kitchen_only?} id="branch-select-kitchen-note" class="alert alert-info mb-4">
        <.icon name="hero-information-circle" class="size-5" />
        <span>
          {gettext(
            "You work in the kitchen. A branch opens only when its kitchen is on and works in the app."
          )}
        </span>
      </div>

      <div class="grid grid-cols-1 gap-4 md:grid-cols-2 lg:grid-cols-3">
        <div
          :if={@network_path}
          id="branch-select-all"
          class="card border border-base-300 bg-base-100"
        >
          <div class="card-body gap-3">
            <h2 id="branch-select-all-title" class="card-title">{gettext("All branches")}</h2>
            <.link
              id="branch-select-all-go"
              href={@network_path}
              aria-describedby="branch-select-all-title"
              class="btn btn-sm btn-outline self-start"
            >
              {gettext("Go")}
            </.link>
          </div>
        </div>
        <%= for %{branch: branch, kitchen?: kitchen?} <- @entries do %>
          <%= if kitchen? do %>
            <div
              id={"branch-select-card-#{branch.id}"}
              class="card border border-base-300 bg-base-100"
            >
              <div class="card-body gap-3">
                <h2 id={"branch-select-title-#{branch.id}"} class="card-title">{branch.name}</h2>
                <.link
                  id={"branch-select-go-#{branch.id}"}
                  href={select_path(branch, @to, @from)}
                  aria-describedby={"branch-select-title-#{branch.id}"}
                  class="btn btn-sm btn-outline self-start"
                >{gettext("Go")}</.link>
              </div>
            </div>
          <% else %>
            <div
              id={"branch-select-disabled-#{branch.id}"}
              class="card border border-dashed border-base-300 bg-base-200/40"
            >
              <div class="card-body gap-3">
                <h2 class="card-title text-base-content/60">{branch.name}</h2>
                <p class="text-sm text-error">{KitchenAccess.message(branch)}</p>
              </div>
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

  defp network_choice_path(staff, source, to) do
    cond do
      Kitchen.account?(staff) or Couriers.account?(staff) or is_binary(to) ->
        nil

      is_nil(source) ->
        ~p"/staff/branches/all"

      true ->
        case StaffBranchPath.transition(source, :network) do
          {:ok, %{path: destination}} ->
            if network_allowed?(staff, destination),
              do: ~p"/staff/branches/all?#{%{from: source}}"

          _ ->
            nil
        end
    end
  end

  defp network_allowed?(staff, destination) do
    path = URI.parse(destination).path

    if path == "/staff/statistics" or String.starts_with?(path, "/staff/analytics/") do
      Identity.can?(staff, "statistics.read") and Identity.can?(staff, "statistics.network")
    else
      true
    end
  end
end
