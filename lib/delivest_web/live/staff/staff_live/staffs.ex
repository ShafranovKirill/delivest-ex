defmodule DelivestWeb.Staff.StaffLive.Staffs do
  use DelivestWeb, :live_view

  alias Delivest.{Identity, Repo}
  alias Delivest.Identity.Staff
  alias DelivestWeb.Staff.StaffLive.StaffFormComponent

  on_mount {DelivestWeb.Hooks.Permission, "staff.read"}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(staff_to_delete: nil)
     |> stream(:staff, [])}
  end

  @impl true
  def handle_params(params, _url, socket) do
    search = Map.get(params, "search", "")

    flop_params =
      if search != "" do
        Map.put(params, "filters", %{
          "0" => %{"field" => "name", "op" => "ilike_and", "value" => search}
        })
      else
        params
      end

    case Identity.list_staff(socket.assigns.current_staff, flop_params,
           preload: [:role, :branches]
         ) do
      {:ok, {staffs, meta}} ->
        socket =
          socket
          |> assign(meta: meta, search: search)
          |> stream(:staff, staffs, reset: true)
          |> apply_action(socket.assigns.live_action, params)

        {:noreply, socket}

      {:error, _meta} ->
        {:noreply, push_patch(socket, to: ~p"/staff/employee")}
    end
  end

  defp apply_action(socket, :index, _params) do
    assign(socket, page_title: gettext("Staff list"), staff: nil)
  end

  defp apply_action(socket, :new, _params) do
    if Identity.can?(socket.assigns.current_staff, "staff.create") do
      assign(socket, page_title: gettext("Create staff"), staff: %Staff{})
    else
      socket
      |> put_flash(:error, gettext("You don't have permission to create staff."))
      |> push_patch(to: ~p"/staff/employee")
    end
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    if Identity.can?(socket.assigns.current_staff, "staff.update") do
      case Identity.get_staff(id, preload: [:role, :branches]) do
        {:ok, staff} -> assign(socket, page_title: gettext("Edit staff"), staff: staff)
        _ -> push_patch(socket, to: ~p"/staff/employee")
      end
    else
      socket
      |> put_flash(:error, gettext("You don't have permission to edit staff."))
      |> push_patch(to: ~p"/staff/employee")
    end
  end

  @impl true
  def handle_event("search", %{"search" => search}, socket) do
    params = build_query_params(socket.assigns, %{"search" => search, "page" => 1})
    {:noreply, push_patch(socket, to: ~p"/staff/employee?#{params}")}
  end

  def handle_event("update_page_size", %{"page_size" => size}, socket) do
    params = build_query_params(socket.assigns, %{"page_size" => size, "page" => 1})
    {:noreply, push_patch(socket, to: ~p"/staff/employee?#{params}")}
  end

  def handle_event("delete_click", %{"id" => id}, socket) do
    if Identity.can?(socket.assigns.current_staff, "staff.delete") do
      {:ok, staff} = Identity.get_staff(id)
      {:noreply, assign(socket, staff_to_delete: staff)}
    else
      {:noreply,
       socket
       |> put_flash(:error, gettext("You don't have permission to delete staff."))
       |> push_patch(to: ~p"/staff/employee")}
    end
  end

  def handle_event("confirm_delete", _, %{assigns: %{staff_to_delete: staff}} = socket) do
    case Identity.soft_delete_staff(socket.assigns.current_staff, staff) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Staff deleted successfully"))
         |> stream_delete(:staff, staff)
         |> assign(staff_to_delete: nil)}

      {:error, _} ->
        {:noreply, socket |> put_flash(:error, gettext("Failed to delete staff"))}
    end
  end

  def handle_event("cancel_delete", _, socket) do
    {:noreply, assign(socket, staff_to_delete: nil)}
  end

  @impl true
  def handle_info({StaffFormComponent, {:saved, staff}}, socket) do
    account = Repo.preload(staff, [:role, :branches])

    action = socket.assigns.live_action

    msg =
      case action do
        :new -> gettext("Staff created successfully")
        :edit -> gettext("Staff updated successfully")
        _ -> gettext("Staff saved successfully")
      end

    {:noreply,
     socket
     |> put_flash(:info, msg)
     |> stream_insert(:staff, account)
     |> push_patch(to: ~p"/staff/employee?#{build_query_params(socket.assigns, %{})}")}
  end

  @impl true
  def handle_info(:staff_updated, socket) do
    {:noreply, socket}
  end

  defp build_query_params(assigns, overrides) do
    meta = assigns.meta

    order_by =
      meta.flop.order_by
      |> List.wrap()
      |> Enum.map(&to_string/1)

    order_directions =
      meta.flop.order_directions
      |> List.wrap()
      |> Enum.map(&to_string/1)

    %{
      "search" => assigns.search,
      "page" => meta.current_page,
      "page_size" => meta.page_size,
      "order_by" => order_by,
      "order_directions" => order_directions
    }
    |> Map.merge(overrides)
    |> Enum.reject(fn {_, v} -> is_nil(v) or v == "" or v == [] end)
    |> Map.new()
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6 p-6">
      <div class="flex justify-between items-center">
        <div>
          <h1 class="text-3xl font-display font-bold text-base-content">{gettext("Staff")}</h1>
          <p class="text-sm text-base-content/60">
            {gettext("Manage system staff accounts and branches access.")}
          </p>
        </div>
        <div class="flex gap-2">
          <.button
            :if={Identity.can?(@current_staff, "staff.create")}
            patch={~p"/staff/employee/new?#{build_query_params(assigns, %{})}"}
            class="btn btn-primary"
          >
            <.icon name="hero-plus" class="size-5" />
            {gettext("Create Staff")}
          </.button>
        </div>
      </div>

      <div class="flex gap-4">
        <.form for={nil} phx-change="search" phx-submit="search" class="w-full max-w-sm">
          <div class="relative">
            <.icon
              name="hero-magnifying-glass"
              class="absolute left-3 top-3.5 size-5 text-base-content/50 z-10"
            />
            <.input
              type="text"
              name="search"
              value={@search}
              placeholder={gettext("Search staff...")}
              class="input input-bordered w-full pl-10"
              phx-debounce="500"
            />
          </div>
        </.form>
      </div>

      <% path_fn = fn overrides -> ~p"/staff/employee?#{build_query_params(assigns, overrides)}" end %>

      <.table id="staff" rows={@streams.staff} meta={@meta} path_fn={path_fn}>
        <:col :let={{_id, stf}} label="ID">
          <span class="font-mono text-xs opacity-50">{String.slice(stf.id, 0..7)}</span>
        </:col>
        <:col :let={{_id, stf}} label={gettext("Login")} sort="login">
          <span class="font-bold">{stf.login}</span>
        </:col>
        <:col :let={{_id, stf}} label={gettext("Name")}>
          {stf.name || "—"}
        </:col>
        <:col :let={{_id, stf}} label={gettext("Role")}>
          <div class="badge badge-outline">{stf.role.name}</div>
        </:col>
        <:col :let={{_id, stf}} label={gettext("Branches")}>
          <div class="max-w-40 text-sm">
            {Enum.map_join(stf.branches, ", ", & &1.name)}
          </div>
        </:col>
        <:col :let={{_id, stf}} label={gettext("Created At")} sort="inserted_at">
          <span class="text-sm opacity-60">{Calendar.strftime(stf.inserted_at, "%d.%m.%Y")}</span>
        </:col>
        <:action :let={{_id, stf}}>
          <div class="flex justify-end gap-2">
            <.button
              :if={Identity.can?(@current_staff, "staff.update")}
              patch={~p"/staff/employee/#{stf.id}/edit?#{build_query_params(assigns, %{})}"}
              class="btn btn-ghost btn-xs btn-square"
            >
              <.icon name="hero-pencil-square" class="size-4" />
            </.button>
            <.button
              :if={Identity.can?(@current_staff, "staff.delete")}
              phx-click="delete_click"
              phx-value-id={stf.id}
              class="btn btn-ghost btn-xs btn-square text-error hover:bg-error/10"
            >
              <.icon name="hero-trash" class="size-4" />
            </.button>
          </div>
        </:action>
      </.table>

      <div class="flex justify-end">
        <.pagination meta={@meta} path_fn={path_fn} />
      </div>

      <.slide_over
        id="staff-slideover"
        show={@live_action in [:new, :edit]}
        title={@page_title}
        on_close={JS.patch(~p"/staff/employee?#{build_query_params(assigns, %{})}")}
      >
        <.live_component
          :if={@staff}
          module={StaffFormComponent}
          id={@staff.id || :new}
          action={@live_action}
          staff={@staff}
          current_staff={@current_staff}
          patch={~p"/staff/employee?#{build_query_params(assigns, %{})}"}
        />
      </.slide_over>

      <.modal
        id="delete-staff-modal"
        show={@staff_to_delete != nil}
        title={gettext("Delete Staff")}
        description={
          gettext("Are you sure you want to delete this staff member? This will revoke their access.")
        }
        confirm_label={gettext("Delete")}
        danger={true}
        on_cancel={JS.push("cancel_delete")}
        on_confirm={JS.push("confirm_delete")}
      />
    </div>
    """
  end
end
