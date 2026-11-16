defmodule DelivestWeb.Staff.SettingsLive.DataTransfer do
  use DelivestWeb, :live_view

  import DelivestWeb.Staff.SettingsComponents

  alias Delivest.Identity
  alias DelivestWeb.StaffBranchPath

  @impl true
  def mount(_params, _session, socket) do
    staff = socket.assigns.current_staff

    if Identity.can?(staff, "admin") or
         editable_branches(staff, socket.assigns.staff_branches) != [] do
      {:ok, assign(socket, page_title: gettext("Data transfer"))}
    else
      {:ok,
       socket
       |> put_flash(:error, gettext("Permission denied"))
       |> redirect(to: ~p"/staff/dashboard")}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    staff = socket.assigns.current_staff
    branches = socket.assigns.staff_branches
    selected = Enum.find(branches, &(&1.slug == params["branch"]))

    if params["branch"] && is_nil(selected) do
      {:noreply,
       socket
       |> put_flash(:error, gettext("Permission denied"))
       |> push_navigate(to: ~p"/staff/settings/data-transfer")}
    else
      editable = editable_branches(staff, branches)

      branch_target =
        case Enum.find(editable, &(&1.id == (selected && selected.id))) do
          nil ->
            case List.first(editable) do
              nil ->
                nil

              first ->
                StaffBranchPath.selection_path(
                  "/staff/branches/#{first.slug}/edit/snapshot",
                  "/staff/settings/data-transfer"
                )
            end

          branch ->
            "/staff/branches/#{branch.slug}/edit/snapshot"
        end

      {:noreply,
       assign(socket,
         settings_scope_branch: selected,
         branch_target: branch_target,
         franchise_snapshot?: Identity.can?(staff, "admin")
       )}
    end
  end

  defp editable_branches(staff, branches) do
    if Identity.can?(staff, "branches.read") and Identity.can?(staff, "branches.update") do
      Enum.filter(branches, &(Identity.authorize(staff, "branches.update", &1.id) == :ok))
    else
      []
    end
  end

  def staff_page_header(assigns) do
    ~H"""
    <.page_header title={gettext("Data transfer")} />
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="data-transfer-content" class="space-y-6">
      <.settings_cards>
        <.settings_card
          :if={@branch_target}
          id="data-transfer-branch"
          navigate={@branch_target}
          icon="hero-archive-box-arrow-down"
          title={gettext("Branch snapshot")}
        />
        <.settings_card
          :if={@franchise_snapshot?}
          id="data-transfer-franchise"
          navigate={~p"/staff/franchise/snapshot"}
          icon="hero-archive-box-arrow-down"
          title={gettext("Franchise snapshot")}
        />
      </.settings_cards>
    </div>
    """
  end
end
