defmodule DelivestWeb.Staff.StaffLive.Staffs do
  use DelivestWeb, :live_view

  alias Delivest.{Identity, Repo}
  alias Delivest.Identity.Staff
  alias DelivestWeb.Staff.StaffLive.StaffFormComponent
  import DelivestWeb.Staff.FoundationComponents, only: [filter_bar: 1]

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
    search = if is_binary(params["search"]), do: params["search"], else: ""

    flop_params =
      if search != "" do
        Map.put(params, "filters", %{
          "0" => %{"field" => "login", "op" => "ilike_and", "value" => search}
        })
      else
        params
      end
      |> Map.put_new("page_size", 25)

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
      with {:ok, %Staff{} = staff} <- Identity.get_staff(id, preload: [:role, :branches]),
           true <- Identity.manages_staff?(socket.assigns.current_staff, staff) do
        assign(socket, page_title: gettext("Edit staff"), staff: staff)
      else
        _ ->
          socket
          |> put_flash(:error, gettext("You don't have permission to edit staff."))
          |> push_patch(to: ~p"/staff/employee")
      end
    else
      socket
      |> put_flash(:error, gettext("You don't have permission to edit staff."))
      |> push_patch(to: ~p"/staff/employee")
    end
  end

  @impl true
  def handle_event("search", %{"search" => search}, socket) do
    search = if is_binary(search), do: search, else: ""
    params = build_query_params(socket.assigns, %{"search" => search, "page" => 1})
    {:noreply, push_patch(socket, to: ~p"/staff/employee?#{params}")}
  end

  def handle_event("search", _, socket), do: {:noreply, socket}

  def handle_event("update_page_size", %{"page_size" => size}, socket) do
    params = build_query_params(socket.assigns, %{"page_size" => size, "page" => 1})
    {:noreply, push_patch(socket, to: ~p"/staff/employee?#{params}")}
  end

  def handle_event("delete_click", %{"id" => id}, socket) do
    with true <- Identity.can?(socket.assigns.current_staff, "staff.delete"),
         {:ok, %Staff{} = staff} <- Identity.get_staff(id, preload: [:role, :branches]),
         true <- manages?(socket.assigns.current_staff, staff) do
      {:noreply, assign(socket, staff_to_delete: staff)}
    else
      _ ->
        {:noreply,
         put_flash(socket, :error, gettext("You don't have permission to delete staff."))}
    end
  end

  def handle_event("confirm_delete", _, %{assigns: %{staff_to_delete: nil}} = socket),
    do: {:noreply, socket}

  def handle_event("confirm_delete", _, %{assigns: %{staff_to_delete: staff}} = socket) do
    case Identity.soft_delete_staff(socket.assigns.current_staff, staff) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Staff deleted successfully"))
         |> assign(staff_to_delete: nil)
         |> push_patch(to: ~p"/staff/employee?#{build_query_params(socket.assigns, %{})}")}

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
     |> push_navigate(to: staff_list_path(socket.assigns, staff.id))}
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

  defp staff_list_path(assigns, staff_id) do
    path = ~p"/staff/employee?#{build_query_params(assigns, %{})}"
    if staff_id, do: path <> "#staff-row-#{staff_id}", else: path
  end

  defp manages?(actor, staff), do: actor.id != staff.id and Identity.manages_staff?(actor, staff)

  def staff_page_header(assigns) do
    ~H"""
    <.page_header
      title={if @live_action in [:new, :edit], do: @page_title, else: gettext("Staff")}
      subtitle={
        if @live_action == :index, do: gettext("Manage system staff accounts and branches access.")
      }
    >
      <:actions>
        <.link
          :if={@live_action in [:new, :edit]}
          id="staff-back-to-list"
          navigate={staff_list_path(assigns, @staff.id)}
          class="btn btn-ghost"
        >{gettext("Back to staff")}</.link>
        <button
          :if={@live_action in [:new, :edit]}
          type="submit"
          form="account-form"
          class="btn btn-primary"
          data-staff-save={if @live_action == :new, do: "create", else: "edit"}
        >{gettext("Save")}</button>
        <.button
          :if={@live_action == :index and Identity.can?(@current_staff, "staff.create")}
          navigate={~p"/staff/employee/new?#{build_query_params(assigns, %{})}"}
          class="btn btn-primary"
        >
          <.icon name="hero-plus" class="size-5" />
          {gettext("Create Staff")}
        </.button>
      </:actions>
    </.page_header>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <%= if @live_action in [:new, :edit] do %>
        <div
          id="staff-edit-page"
          class="mx-auto max-w-4xl rounded-box border border-base-300 bg-base-100"
        >
          <.live_component
            :if={@staff}
            module={StaffFormComponent}
            id={@staff.id || :new}
            action={@live_action}
            staff={@staff}
            current_staff={@current_staff}
            patch={staff_list_path(assigns, @staff.id)}
          />
        </div>
      <% else %>
        <.filter_bar
          id="staff-filter"
          query={@search}
          query_name="search"
          query_placeholder={gettext("Search staff...")}
          event="search"
          reset_path={~p"/staff/employee"}
        />

        <% path_fn = fn overrides -> ~p"/staff/employee?#{build_query_params(assigns, overrides)}" end %>

        <.table
          id="staff"
          rows={@streams.staff}
          meta={@meta}
          path_fn={path_fn}
          staff_id={to_string(@current_staff.id)}
          list_id="staff"
          empty_title={
            if @search == "", do: gettext("No records yet"), else: gettext("Nothing found")
          }
        >
          <:col :let={{_id, stf}} key="id" label="ID" secondary>
            <span class="font-mono text-xs opacity-50">{String.slice(stf.id, 0..7)}</span>
          </:col>
          <:col :let={{_id, stf}} label={gettext("Login")} sort="login">
            <span id={"staff-row-#{stf.id}"} class="font-bold scroll-mt-24">{stf.login}</span>
          </:col>
          <:col :let={{_id, stf}} label={gettext("Name")}>
            {stf.name || "—"}
          </:col>
          <:col :let={{_id, stf}} label={gettext("Role")}>
            <span class="font-bold">{stf.role.name}</span>
          </:col>
          <:col :let={{_id, stf}} key="branches" label={gettext("Branches")} secondary>
            <div class="max-w-40 text-sm">
              {Enum.map_join(stf.branches, ", ", & &1.name)}
            </div>
          </:col>
          <:col :let={{_id, stf}} label={gettext("Created At")} sort="inserted_at" secondary>
            <span class="text-sm opacity-60">{Calendar.strftime(stf.inserted_at, "%d.%m.%Y")}</span>
          </:col>
          <:action :let={{_id, stf}}>
            <div class="flex justify-end gap-2">
              <.button
                :if={
                  Identity.can?(@current_staff, "staff.update") and
                    Identity.manages_staff?(@current_staff, stf)
                }
                navigate={~p"/staff/employee/#{stf.id}/edit?#{build_query_params(assigns, %{})}"}
                class="btn btn-ghost btn-xs btn-square"
              >
                <.icon name="hero-pencil-square" class="size-4" />
              </.button>
              <.button
                :if={Identity.can?(@current_staff, "staff.delete") and manages?(@current_staff, stf)}
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
          <.pagination meta={@meta} path_fn={path_fn} page_sizes={[25, 50, 100]} />
        </div>

        <.modal
          id="delete-staff-modal"
          show={@staff_to_delete != nil}
          title={gettext("Delete Staff")}
          description={
            gettext(
              "Are you sure you want to delete this staff member? This will revoke their access."
            )
          }
          confirm_label={gettext("Delete")}
          danger={true}
          on_cancel={JS.push("cancel_delete")}
          on_confirm={JS.push("confirm_delete")}
        />
      <% end %>
    </div>
    """
  end
end
