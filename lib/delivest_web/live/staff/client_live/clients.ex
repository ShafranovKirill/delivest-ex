defmodule DelivestWeb.Staff.ClientLive.Clients do
  use DelivestWeb, :live_view

  alias Delivest.Identity
  alias Delivest.Identity.Client
  alias Delivest.Identity.Clients
  alias DelivestWeb.Staff.ClientLive.ClientFormComponent

  on_mount {DelivestWeb.Hooks.Permission, "clients.read"}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       client_to_delete: nil,
       search: "",
       selected_status: nil
     )
     |> stream(:clients, [])}
  end

  @impl true
  def handle_params(params, _url, socket) do
    flop_params = prepare_flop_params(params)

    case Clients.list_clients(socket.assigns.current_staff, flop_params) do
      {:ok, {clients, meta}} ->
        socket =
          socket
          |> assign(
            meta: meta,
            search: Map.get(params, "search", ""),
            selected_status: Flop.Filter.get_value(meta.flop.filters, :status)
          )
          |> stream(:clients, clients, reset: true)
          |> apply_action(socket.assigns.live_action, params)

        {:noreply, socket}

      {:error, _reason_or_meta} ->
        {:noreply, push_patch(socket, to: ~p"/staff/clients")}
    end
  end

  defp prepare_flop_params(params) do
    case Map.get(params, "search") do
      val when val in [nil, ""] ->
        params

      val ->
        filters = Map.get(params, "filters", %{})
        next_idx = map_size(filters)

        new_filters =
          Map.put(filters, to_string(next_idx), %{
            "field" => "search_term",
            "op" => "ilike",
            "value" => String.trim(val)
          })

        Map.put(params, "filters", new_filters)
    end
  end

  defp apply_action(socket, :index, _params) do
    assign(socket, page_title: gettext("Clients List"), client: nil)
  end

  defp apply_action(socket, :new, _params) do
    if Identity.can?(socket.assigns.current_staff, "clients.create") do
      assign(socket, page_title: gettext("Create Client"), client: %Client{})
    else
      socket
      |> put_flash(:error, gettext("You don't have permission to create clients."))
      |> push_patch(to: ~p"/staff/clients")
    end
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    if Identity.can?(socket.assigns.current_staff, "clients.update") do
      case Clients.get_client(socket.assigns.current_staff, id) do
        {:ok, %Client{} = client} ->
          assign(socket, page_title: gettext("Edit Client"), client: client)

        _ ->
          push_patch(socket, to: ~p"/staff/clients")
      end
    else
      socket
      |> put_flash(:error, gettext("You don't have permission to edit clients."))
      |> push_patch(to: ~p"/staff/clients")
    end
  end

  @impl true
  def handle_event("filter", params, socket) do
    search = params["search"]
    status = params["status"]

    filters =
      []
      |> maybe_add_filter(:status, "==", status)
      |> map_to_flop_format()

    query_params =
      build_query_params(socket.assigns, %{
        "search" => search,
        "filters" => filters,
        "page" => 1
      })

    {:noreply, push_patch(socket, to: ~p"/staff/clients?#{query_params}")}
  end

  def handle_event("update_page_size", %{"page_size" => size}, socket) do
    params = build_query_params(socket.assigns, %{"page_size" => size, "page" => 1})
    {:noreply, push_patch(socket, to: ~p"/staff/clients?#{params}")}
  end

  def handle_event("delete_click", %{"id" => id}, socket) do
    if Identity.can?(socket.assigns.current_staff, "clients.delete") do
      case Clients.get_client(socket.assigns.current_staff, id) do
        {:ok, client} ->
          {:noreply, assign(socket, client_to_delete: client)}

        _ ->
          {:noreply, socket}
      end
    else
      {:noreply,
       socket
       |> put_flash(:error, gettext("You don't have permission to delete clients."))
       |> push_patch(to: ~p"/staff/clients")}
    end
  end

  def handle_event("confirm_delete", _, %{assigns: %{client_to_delete: client}} = socket) do
    case Clients.soft_delete_client(socket.assigns.current_staff, client) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Client deleted successfully"))
         |> stream_delete(:clients, client)
         |> assign(client_to_delete: nil)}

      {:error, _} ->
        {:noreply, socket |> put_flash(:error, gettext("Failed to delete client"))}
    end
  end

  def handle_event("cancel_delete", _, socket) do
    {:noreply, assign(socket, client_to_delete: nil)}
  end

  @impl true
  def handle_info({ClientFormComponent, {:saved, client}}, socket) do
    action = socket.assigns.live_action

    msg =
      case action do
        :new -> gettext("Client created successfully")
        :edit -> gettext("Client updated successfully")
        _ -> gettext("Client saved successfully")
      end

    {:noreply,
     socket
     |> put_flash(:info, msg)
     |> stream_insert(:clients, client)
     |> push_patch(to: ~p"/staff/clients?#{build_query_params(socket.assigns, %{})}")}
  end

  defp maybe_add_filter(filters, _field, _op, val) when val in [nil, ""], do: filters

  defp maybe_add_filter(filters, field, op, val) do
    [%{"field" => to_string(field), "op" => op, "value" => val} | filters]
  end

  defp map_to_flop_format(list_of_filters) do
    list_of_filters
    |> Enum.with_index()
    |> Map.new(fn {filter, idx} -> {to_string(idx), filter} end)
  end

  defp with_indexed_map(list) do
    list
    |> Enum.map(fn
      %Flop.Filter{} = f -> Map.from_struct(f)
      f -> f
    end)
    |> Enum.with_index()
    |> Map.new(fn {f, idx} -> {to_string(idx), f} end)
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

    filters_for_query =
      meta.flop.filters
      |> List.wrap()
      |> Enum.map(fn
        %Flop.Filter{} = f -> Map.from_struct(f)
        f -> f
      end)
      |> with_indexed_map()

    %{
      "search" => assigns.search,
      "page" => meta.current_page,
      "page_size" => meta.page_size,
      "order_by" => order_by,
      "order_directions" => order_directions,
      "filters" => filters_for_query
    }
    |> Map.merge(overrides)
    |> Enum.reject(fn {_, v} -> is_nil(v) or v == "" or v == [] or v == %{} end)
    |> Map.new()
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6 p-6">
      <div class="flex justify-between items-center">
        <div>
          <h1 class="text-3xl font-display font-bold text-base-content">{gettext("Clients")}</h1>
          <p class="text-sm text-base-content/60">
            {gettext("Manage system clients, status, and information.")}
          </p>
        </div>
        <div class="flex gap-2">
          <.button
            :if={Identity.can?(@current_staff, "clients.create")}
            patch={~p"/staff/clients/new?#{build_query_params(assigns, %{})}"}
            class="btn btn-primary"
          >
            <.icon name="hero-user-plus" class="size-5" />
            {gettext("Create Client")}
          </.button>
        </div>
      </div>

      <.form
        for={nil}
        phx-change="filter"
        class="flex gap-4 items-center justify-between flex-wrap w-full"
      >
        <div class="relative w-full sm:max-w-sm">
          <.icon
            name="hero-magnifying-glass"
            class="absolute left-3 top-3.5 size-5 text-base-content/50 z-10"
          />
          <.input
            type="text"
            name="search"
            value={@search}
            placeholder={gettext("Search by name or phone...")}
            class="input input-bordered w-full pl-10"
            phx-debounce="500"
          />
        </div>

        <div class="flex items-center gap-3 flex-wrap sm:flex-nowrap">
          <select name="status" class="select select-bordered w-full sm:w-48 shrink-0">
            <option value="">{gettext("All statuses")}</option>
            <option value="guest" selected={to_string(@selected_status) == "guest"}>
              {gettext("Guest")}
            </option>
            <option value="active" selected={to_string(@selected_status) == "active"}>
              {gettext("Active")}
            </option>
            <option value="blocked" selected={to_string(@selected_status) == "blocked"}>
              {gettext("Blocked")}
            </option>
          </select>
        </div>
      </.form>

      <% path_fn = fn overrides -> ~p"/staff/clients?#{build_query_params(assigns, overrides)}" end %>

      <.table id="clients" rows={@streams.clients} meta={@meta} path_fn={path_fn}>
        <:col :let={{_id, client}} label={gettext("Name")} sort="name">
          <span class="font-bold">{client.name || "—"}</span>
        </:col>

        <:col :let={{_id, client}} label={gettext("Phone")} sort="phone">
          <span class="font-mono">{client.phone}</span>
        </:col>

        <:col :let={{_id, client}} label={gettext("Status")} sort="status">
          <%= case client.status do %>
            <% :active -> %>
              <span class="badge badge-success badge-sm whitespace-nowrap">{gettext("Active")}</span>
            <% :guest -> %>
              <span class="badge badge-info badge-sm whitespace-nowrap">{gettext("Guest")}</span>
            <% :blocked -> %>
              <span class="badge badge-error badge-sm text-error-content whitespace-nowrap">
                {gettext("Blocked")}
              </span>
            <% _ -> %>
              <span class="badge badge-ghost badge-sm">{client.status}</span>
          <% end %>
        </:col>

        <:col :let={{_id, client}} label={gettext("Created At")} sort="inserted_at">
          <span class="text-sm opacity-60">
            {Calendar.strftime(client.inserted_at, "%d.%m.%Y %H:%M")}
          </span>
        </:col>

        <:action :let={{_id, client}}>
          <div class="flex justify-end gap-2">
            <.button
              :if={Identity.can?(@current_staff, "clients.update")}
              patch={~p"/staff/clients/#{client.id}/edit?#{build_query_params(assigns, %{})}"}
              class="btn btn-ghost btn-xs btn-square"
            >
              <.icon name="hero-pencil-square" class="size-4" />
            </.button>
            <.button
              :if={Identity.can?(@current_staff, "clients.delete")}
              phx-click="delete_click"
              phx-value-id={client.id}
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
        id="client-slideover"
        show={@live_action in [:new, :edit]}
        title={@page_title}
        on_close={JS.patch(~p"/staff/clients?#{build_query_params(assigns, %{})}")}
      >
        <.live_component
          :if={@client}
          module={ClientFormComponent}
          id={@client.id || :new}
          action={@live_action}
          client={@client}
          current_staff={@current_staff}
          patch={~p"/staff/clients?#{build_query_params(assigns, %{})}"}
        />
      </.slide_over>

      <.modal
        id="delete-client-modal"
        show={@client_to_delete != nil}
        title={gettext("Delete Client")}
        description={
          gettext("Are you sure you want to delete this client? This action cannot be easily undone.")
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
