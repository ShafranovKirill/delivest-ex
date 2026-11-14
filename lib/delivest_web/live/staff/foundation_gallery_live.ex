defmodule DelivestWeb.Staff.FoundationGalleryLive do
  @moduledoc "Development and test only foundation gallery. Fixtures never touch production data."
  use DelivestWeb, :live_view
  import DelivestWeb.Staff.FoundationComponents
  alias DelivestWeb.Staff.Foundation.{FormState, ListState}

  @base_products [
    %{
      id: "p1",
      name: "Classic pizza with a deliberately long product name",
      price: "890 ₽",
      status: "Active"
    },
    %{id: "p2", name: "Mushroom soup", price: "390 ₽", status: "Paused"},
    %{id: "p3", name: "Orange juice", price: "250 ₽", status: "Active"}
  ]
  @products @base_products ++
              Enum.map(4..32, fn id ->
                %{
                  id: "p#{id}",
                  name: "Fixture product #{id}",
                  price: "#{id * 10} ₽",
                  status: if(rem(id, 2) == 0, do: "Active", else: "Paused")
                }
              end)
  @columns [
    %{
      key: "name",
      field: :name,
      label: "Name",
      sortable: true,
      numeric: false,
      secondary: false,
      link: true,
      required: true
    },
    %{
      key: "price",
      field: :price,
      label: "Price",
      sortable: false,
      numeric: true,
      secondary: false
    },
    %{
      key: "status",
      field: :status,
      label: "Status",
      sortable: false,
      numeric: false,
      secondary: true
    }
  ]
  @saved %{"name" => "Demo branch", "code" => "DEMO", "slug" => "demo"}
  @latest %{"name" => "Latest branch", "code" => "DEMO", "slug" => "demo"}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Foundation gallery",
       foundation_workspace: true,
       gallery_view: "list",
       selected_id: nil,
       form_state: FormState.new(@saved),
       panel: false,
       panel_draft: "Fixture note",
       panel_saved: "Fixture note",
       panel_confirm: false,
       density: "normal",
       picker_open: false,
       picker_ids: [],
       scope_query: "",
       feature_desired: true,
       pending_nav: nil,
       allow_leave: false,
       bulk_pending: false,
       bulk_result: nil,
       columns: @columns,
       integrations: integration_fixtures()
     )
     |> assign_form()}
  end

  @impl true
  def handle_params(params, url, socket) do
    view = if params["view"] in ~w(queue list entity settings), do: params["view"], else: "list"

    parsed_url = URI.parse(url)
    target_url = parsed_url.path <> if(parsed_url.query, do: "?" <> parsed_url.query, else: "")

    if socket.assigns[:gallery_view] == "settings" and view != "settings" and
         not socket.assigns[:allow_leave] and
         FormState.dirty?(socket.assigns.form_state) do
      {:noreply,
       socket
       |> assign(
         form_state: FormState.request_leave(socket.assigns.form_state),
         pending_nav: %{to: target_url, kind: "patch"}
       )
       |> push_patch(to: socket.assigns.current_url)}
    else
      apply_gallery_params(params, view, target_url, socket)
    end
  end

  defp apply_gallery_params(params, view, target_url, socket) do
    scope = if params["scope"] in ["network", "branch-a"], do: params["scope"], else: "network"

    list =
      ListState.from_params(params,
        sorts: ["name", "price"],
        filters: ["status"],
        scope: scope
      )

    {products, total} = fetch_fixture_page(list)

    return_path =
      if is_binary(params["return"]) and
           String.starts_with?(params["return"], "/staff/foundation-gallery?"),
         do: params["return"],
         else: gallery_path("list", list)

    selected_product = Enum.find(@products, &(&1.id == params["id"]))

    products =
      Enum.map(products, fn product ->
        Map.put(product, :path, entity_path(product.id, gallery_path("list", list)))
      end)

    {:noreply,
     assign(socket,
       gallery_view: view,
       list: list,
       products: products,
       total: total,
       selected_product: selected_product,
       return_path: return_path,
       selected_id: params["id"],
       current_url: target_url,
       pending_nav:
         if(socket.assigns.form_state.confirmation == :leave,
           do: socket.assigns.pending_nav,
           else: nil
         ),
       allow_leave: false,
       bulk_pending: false
     )}
  end

  @impl true
  def handle_event("filter", %{"q" => q}, socket) do
    list = ListState.change(socket.assigns.list, %{query: q})
    {:noreply, push_patch(socket, to: gallery_path(socket.assigns.gallery_view, list))}
  end

  def handle_event("select", %{"id" => id}, socket) do
    current = socket.assigns.list.selected

    ids =
      if MapSet.member?(current, id),
        do: MapSet.delete(current, id),
        else: MapSet.put(current, id)

    list = ListState.select(socket.assigns.list, ids, Enum.map(socket.assigns.products, & &1.id))
    {:noreply, assign(socket, list: list)}
  end

  def handle_event("validate", %{"branch" => params}, socket) do
    state = FormState.edit(socket.assigns.form_state, params)
    {:noreply, socket |> assign(form_state: state) |> assign_form()}
  end

  def handle_event("save", %{"branch" => params}, socket) do
    state = FormState.edit(socket.assigns.form_state, params)

    case FormState.begin_save(state) do
      {:error, state} ->
        {:noreply, assign(socket, form_state: state)}

      {:ok, pending} ->
        case validate_branch(params) do
          :ok ->
            {:noreply,
             socket |> assign(form_state: FormState.saved(pending, params)) |> assign_form()}

          errors ->
            {:noreply,
             socket |> assign(form_state: FormState.failed(pending, errors)) |> assign_form()}
        end
    end
  end

  def handle_event("cancel", _params, socket),
    do:
      {:noreply, assign(socket, form_state: FormState.request_cancel(socket.assigns.form_state))}

  def handle_event("stay", _params, socket),
    do:
      {:noreply,
       assign(socket, form_state: FormState.stay(socket.assigns.form_state), pending_nav: nil)}

  def handle_event("request_leave", %{"to" => to} = params, socket) do
    if (to == "/staff" or String.starts_with?(to, "/staff/")) and
         FormState.dirty?(socket.assigns.form_state) do
      {:noreply,
       assign(socket,
         form_state: FormState.request_leave(socket.assigns.form_state),
         pending_nav: %{to: to, kind: params["kind"] || "redirect"}
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("confirm_leave", _params, socket) do
    if socket.assigns.form_state.confirmation == :leave and socket.assigns.pending_nav do
      %{to: to, kind: kind} = socket.assigns.pending_nav

      socket =
        socket
        |> assign(
          form_state: FormState.discard(socket.assigns.form_state),
          pending_nav: nil,
          allow_leave: true
        )
        |> assign_form()

      case kind do
        "patch" -> {:noreply, push_patch(socket, to: to)}
        "ordinary" -> {:noreply, redirect(socket, to: to)}
        _ -> {:noreply, push_navigate(socket, to: to)}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("discard", _params, socket) do
    {:noreply,
     socket |> assign(form_state: FormState.discard(socket.assigns.form_state)) |> assign_form()}
  end

  def handle_event("open_panel", _params, socket), do: {:noreply, assign(socket, panel: true)}

  def handle_event("panel_change", %{"note" => note}, socket),
    do: {:noreply, assign(socket, panel_draft: note)}

  def handle_event("panel_save", _params, socket),
    do: {:noreply, assign(socket, panel_saved: socket.assigns.panel_draft)}

  def handle_event("stay_panel", _params, socket),
    do: {:noreply, assign(socket, panel_confirm: false)}

  def handle_event("discard_panel", _params, socket),
    do:
      {:noreply,
       assign(socket, panel: false, panel_confirm: false, panel_draft: socket.assigns.panel_saved)}

  def handle_event("density", %{"value" => value}, socket) when value in ~w(normal compact),
    do: {:noreply, assign(socket, density: value)}

  def handle_event("scope_search", %{"q" => query}, socket) when is_binary(query),
    do: {:noreply, assign(socket, scope_query: String.slice(query, 0, 80))}

  def handle_event("scope_search", _params, socket), do: {:noreply, socket}

  def handle_event("toggle_feature", _params, socket),
    do: {:noreply, assign(socket, feature_desired: not socket.assigns.feature_desired)}

  def handle_event("check_connection", %{"id" => id}, socket) do
    integrations =
      Enum.map(socket.assigns.integrations, fn integration ->
        if integration.id == id,
          do: %{
            integration
            | connection_status: :checking,
              connection_summary: "Fixture check in progress"
          },
          else: integration
      end)

    {:noreply, assign(socket, integrations: integrations)}
  end

  def handle_event("finish_connection_check", %{"id" => id}, socket) do
    integrations =
      Enum.map(socket.assigns.integrations, fn integration ->
        if integration.id == id and integration.connection_status == :checking,
          do: %{
            integration
            | connection_status: integration.connection_result,
              connection_summary: "Fixture result; no provider call"
          },
          else: integration
      end)

    {:noreply, assign(socket, integrations: integrations)}
  end

  def handle_event("open_picker", _params, socket),
    do: {:noreply, assign(socket, picker_open: true, panel: false)}

  def handle_event("close_panel", _params, socket) do
    if socket.assigns.panel_draft == socket.assigns.panel_saved,
      do: {:noreply, assign(socket, panel: false)},
      else: {:noreply, assign(socket, panel_confirm: true)}
  end

  def handle_event("request_close", _params, socket) do
    if socket.assigns.panel and socket.assigns.panel_draft != socket.assigns.panel_saved,
      do: {:noreply, assign(socket, panel_confirm: true)},
      else:
        {:noreply,
         assign(socket, form_state: FormState.request_cancel(socket.assigns.form_state))}
  end

  def handle_event("simulate_conflict", _params, socket),
    do: {:noreply, assign(socket, form_state: FormState.conflict(socket.assigns.form_state))}

  def handle_event("conflict_retry", _params, socket),
    do:
      {:noreply,
       socket
       |> assign(
         form_state: FormState.resolve_conflict(socket.assigns.form_state, @latest, :retry)
       )
       |> assign_form()}

  def handle_event("conflict_reload", _params, socket),
    do:
      {:noreply, assign(socket, form_state: FormState.request_reload(socket.assigns.form_state))}

  def handle_event("confirm_reload", _params, socket),
    do:
      {:noreply,
       socket
       |> assign(form_state: FormState.reload_latest(socket.assigns.form_state, @latest))
       |> assign_form()}

  def handle_event("simulate_read_only", _params, socket),
    do: {:noreply, assign(socket, form_state: FormState.read_only(socket.assigns.form_state))}

  def handle_event("simulate_server_error", _params, socket),
    do:
      {:noreply,
       socket
       |> assign(
         form_state:
           FormState.failed(socket.assigns.form_state, %{
             "gallery-branch-form" => "Server unavailable. Retry."
           })
       )
       |> assign_form()}

  def handle_event("request_bulk", _params, socket) do
    if ListState.selected_count(socket.assigns.list) > 0,
      do: {:noreply, assign(socket, bulk_pending: true)},
      else: {:noreply, socket}
  end

  def handle_event("cancel_bulk", _params, socket),
    do: {:noreply, assign(socket, bulk_pending: false)}

  def handle_event("confirm_bulk", _params, socket) do
    if socket.assigns.bulk_pending do
      result = Enum.map(socket.assigns.list.selected, &{&1, :accepted})

      {:noreply,
       assign(socket,
         bulk_pending: false,
         bulk_result: result,
         list: %{socket.assigns.list | selected: MapSet.new()}
       )}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:picker_saved, ids}, socket),
    do: {:noreply, assign(socket, picker_open: false, picker_ids: ids)}

  def handle_info(:picker_cancelled, socket), do: {:noreply, assign(socket, picker_open: false)}

  defp assign_form(socket) do
    draft = socket.assigns.form_state.draft

    changeset = Delivest.Identity.Branch.changeset(%Delivest.Identity.Branch{}, draft)

    changeset =
      if socket.assigns.form_state.status == :error,
        do: %{changeset | action: :insert},
        else: changeset

    assign(socket, form: to_form(changeset, as: :branch))
  end

  defp validate_branch(params) do
    changeset = Delivest.Identity.Branch.changeset(%Delivest.Identity.Branch{}, params)

    if changeset.valid? do
      :ok
    else
      Map.new(changeset.errors, fn {field, error} ->
        {"branch-#{field}",
         "#{field_label(field)}: #{DelivestWeb.CoreComponents.translate_error(error)}"}
      end)
    end
  end

  defp field_label(:name), do: gettext("Name")
  defp field_label(:code), do: gettext("Code")
  defp field_label(:slug), do: gettext("Slug")
  defp field_label(field), do: Phoenix.Naming.humanize(field)

  defp fetch_fixture_page(list) do
    filtered =
      Enum.filter(@products, fn product ->
        in_scope = list.scope == "network" or product.id in Enum.map(1..16, &"p#{&1}")

        (list.query == "" or
           String.contains?(String.downcase(product.name), String.downcase(list.query))) and
          list.filters["status"] in [nil, product.status] and in_scope
      end)

    sorted =
      Enum.sort_by(
        filtered,
        fn product -> Map.get(product, String.to_existing_atom(list.sort)) end,
        if(list.direction == "desc", do: :desc, else: :asc)
      )

    {Enum.slice(sorted, (list.page - 1) * list.per_page, list.per_page), length(sorted)}
  end

  defp entity_path(id, return_path),
    do:
      "/staff/foundation-gallery?" <>
        URI.encode_query(%{"view" => "entity", "id" => id, "return" => return_path})

  defp gallery_path(view, list) do
    "/staff/foundation-gallery?" <>
      URI.encode_query(Map.put(ListState.params(list), "view", view))
  end

  defp scope_options(list, view, query) do
    [%{id: "network", label: "Network"}, %{id: "branch-a", label: "Demo branch"}]
    |> Enum.filter(&String.contains?(String.downcase(&1.label), String.downcase(query)))
    |> Enum.map(fn option ->
      Map.put(option, :path, gallery_path(view, ListState.change(list, %{scope: option.id})))
    end)
  end

  defp integration_fixtures do
    [
      %{
        id: "unconfigured",
        title: "Delivery gateway",
        configured: false,
        desired: false,
        effective: false,
        connection_status: :unknown,
        connection_result: :error,
        connection_summary: "No credentials; connection has not been checked",
        capabilities: [%{label: "Orders", state: "Unavailable"}],
        dependencies: [],
        issues: ["Credentials missing"],
        obligations: []
      },
      %{
        id: "configured",
        title: "Payment provider",
        configured: true,
        desired: false,
        effective: false,
        connection_status: :ok,
        connection_result: :ok,
        connection_summary: "Fixture connection is healthy; activation is off",
        capabilities: [%{label: "Payments", state: "Available"}],
        dependencies: [],
        issues: [],
        obligations: []
      },
      %{
        id: "blocked",
        title: "Courier service",
        configured: true,
        desired: true,
        effective: false,
        connection_status: :error,
        connection_result: :error,
        connection_summary: "Fixture connection failed",
        capabilities: [%{label: "Dispatch", state: "Unavailable"}],
        dependencies: ["Branch delivery enabled"],
        issues: ["Dependency unavailable"],
        obligations: ["Finish accepted orders"]
      },
      %{
        id: "enabled",
        title: "Receipt service",
        configured: true,
        desired: true,
        effective: true,
        connection_status: :ok,
        connection_result: :ok,
        connection_summary: "Fixture connection is healthy",
        capabilities: [%{label: "Receipts", state: "Available"}],
        dependencies: ["Credentials valid"],
        issues: [],
        obligations: ["Complete pending receipts"]
      },
      %{
        id: "stale",
        title: "Loyalty service",
        configured: true,
        desired: true,
        effective: false,
        connection_status: :stale,
        connection_result: :ok,
        connection_summary: "Last fixture check is stale",
        capabilities: [%{label: "Rewards", state: "Unknown"}],
        dependencies: [],
        issues: ["Check the connection before activation"],
        obligations: []
      }
    ]
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="foundation-gallery" class="foundation-workspace space-y-6" data-density={@density}>
      <.workspace_header
        id="gallery-header"
        title={page_title(@gallery_view)}
        scope="Network · Fixture data"
        description="Reusable staff page patterns"
      >
        <:primary>
          <button id="gallery-primary" type="button" class="btn btn-primary" phx-click="open_panel">New item</button>
        </:primary>
      </.workspace_header>
      <.section_nav
        id="gallery-tabs"
        active={@gallery_view}
        items={
          Enum.map(
            ~w(queue list entity settings),
            &%{id: &1, label: String.capitalize(&1), path: "/staff/foundation-gallery?view=#{&1}"}
          )
        }
      />
      <.scope_switcher
        id="gallery-scope"
        scope={if(@list.scope == "network", do: "Network", else: "Demo branch")}
        query={@scope_query}
        options={scope_options(@list, @gallery_view, @scope_query)}
      />

      <section :if={@gallery_view == "queue"} id="gallery-queue" class="space-y-4">
        <.state_notice
          id="queue-freshness"
          kind={:loading}
          title="Updated just now · Connection active"
        />
        <div class="grid gap-3 sm:grid-cols-2">
          <article class="rounded-box border border-base-300 bg-base-100 p-4">
            <h2 class="font-semibold">Order #1001</h2><.status_badge
              id="queue-status"
              label="Preparing"
              tone={:warning}
            /><p>Pickup · 12:30</p><button class="btn btn-ghost" type="button" phx-click="open_panel">View order</button>
          </article>
        </div>
        <.state_notice
          id="queue-disconnected-example"
          kind={:error}
          title="Connection lost · Reconnect before acting"
        />
      </section>

      <section :if={@gallery_view == "list"} id="gallery-list" class="space-y-4">
        <div id="gallery-density" class="flex gap-2">
          <button
            type="button"
            phx-click="density"
            phx-value-value="normal"
            aria-pressed={@density == "normal"}
            class="btn btn-ghost"
          >Normal</button><button
            type="button"
            phx-click="density"
            phx-value-value="compact"
            aria-pressed={@density == "compact"}
            class="btn btn-ghost"
          >Compact</button>
        </div>
        <.column_chooser
          id="gallery-columns"
          staff_id={to_string(@current_staff.id)}
          list_id="products"
          table_id="gallery-products-table"
          columns={@columns}
        />
        <.filter_bar
          id="product-filters"
          query={@list.query}
          reset_path="/staff/foundation-gallery?view=list"
        />
        <.data_table
          id="gallery-products"
          rows={@products}
          columns={@columns}
          selected={@list.selected}
          reset_path="/staff/foundation-gallery?view=list"
          empty_kind={ListState.empty_kind(length(@products), @list)}
          page={@list.page}
          per_page={@list.per_page}
          pages={max(1, ceil(@total / @list.per_page))}
          page_path={fn page -> gallery_path("list", %{@list | page: page}) end}
          per_page_path={
            fn size -> gallery_path("list", ListState.change(@list, %{per_page: size})) end
          }
          sort_path={
            fn sort ->
              gallery_path(
                "list",
                ListState.change(@list, %{
                  sort: sort,
                  direction: if(@list.direction == "asc", do: "desc", else: "asc")
                })
              )
            end
          }
        >
          <:cell :let={row} key="status">
            <.status_badge
              id={"product-status-#{row.id}"}
              label={row.status}
              tone={if(row.status == "Active", do: :success, else: :warning)}
            />
          </:cell>
          <:action :let={row}>
            <button
              id={"product-action-#{row.id}"}
              type="button"
              phx-click="open_panel"
              aria-label={"Preview #{row.name}"}
              class="btn btn-ghost"
            >Preview</button>
          </:action>
        </.data_table>
        <.bulk_action_bar id="gallery-bulk" count={ListState.selected_count(@list)}>
          <button
            id="gallery-bulk-request"
            type="button"
            phx-click="request_bulk"
            class="btn btn-ghost"
          >Archive selected on this page</button>
        </.bulk_action_bar>
        <p :if={@bulk_result} id="gallery-bulk-result" role="status">
          {length(@bulk_result)} fixture records accepted
        </p>
      </section>

      <section :if={@gallery_view == "entity"} id="gallery-entity" class="space-y-4">
        <.status_badge
          :if={@selected_product}
          id="entity-status"
          label={@selected_product.status}
          tone={if(@selected_product.status == "Active", do: :success, else: :warning)}
        />
        <h2 :if={@selected_product} class="text-xl font-semibold">{@selected_product.name}</h2>
        <p :if={@selected_product}>{@selected_product.price} · Food · Available in 2 branches</p>
        <.state_notice
          :if={is_nil(@selected_product)}
          id="entity-missing"
          kind={:error}
          title="Product not found"
        />
        <.link patch={@return_path} class="btn btn-ghost">Back to list</.link>
        <.form_section id="entity-details" title="Details" description="Key data and related records">
          <p>SKU: DEMO-001</p><p>Related categories: Pizza</p>
        </.form_section>
        <.state_notice id="entity-history" kind={:empty} title="No history yet" />
        <button id="open-product-picker" type="button" phx-click="open_picker" class="btn btn-ghost">Select related products</button>
        <p id="picker-result" role="status">{length(@picker_ids)} related products selected</p>
      </section>

      <section :if={@gallery_view == "settings"} id="gallery-settings" class="space-y-6">
        <.form
          for={@form}
          id="gallery-branch-form"
          phx-hook="FoundationDirty"
          data-dirty={to_string(FormState.dirty?(@form_state))}
          phx-change="validate"
          phx-submit="save"
          class="foundation-form"
        >
          <.error_summary id="branch-errors" errors={@form_state.errors} />
          <.form_section
            id="branch-general"
            title="Branch details"
            description="One save applies to this form"
          >
            <.input
              field={@form[:name]}
              id="branch-name"
              label="Name"
              disabled={not @form_state.writable?}
            />
            <.input
              field={@form[:code]}
              id="branch-code"
              label="Code"
              disabled={not @form_state.writable?}
            />
            <.input
              field={@form[:slug]}
              id="branch-slug"
              label="Slug"
              disabled={not @form_state.writable?}
            />
          </.form_section>
          <.form_actions id="branch-actions" state={@form_state}>
            <:recovery>
              <button
                id="conflict-retry"
                type="button"
                phx-click="conflict_retry"
                class="btn btn-ghost"
              >Review latest and retry</button><button
                id="conflict-reload"
                type="button"
                phx-click="conflict_reload"
                class="btn btn-ghost"
              >Reload latest</button>
            </:recovery>
          </.form_actions>
        </.form>
        <div class="flex flex-wrap gap-2">
          <button
            id="simulate-conflict"
            type="button"
            phx-click="simulate_conflict"
            class="btn btn-ghost"
          >Simulate conflict</button><button
            id="simulate-read-only"
            type="button"
            phx-click="simulate_read_only"
            class="btn btn-ghost"
          >Simulate view only</button><button
            id="simulate-server-error"
            type="button"
            phx-click="simulate_server_error"
            class="btn btn-ghost"
          >Simulate server error</button>
        </div>
        <h2 class="text-xl font-semibold">Integration states</h2>
        <.feature_card
          id="feature-example"
          title="Online payment"
          desired={@feature_desired}
          effective={false}
          reason="Payment provider unavailable"
        >
          <:action>
            <button id="feature-toggle" type="button" phx-click="toggle_feature" class="btn btn-ghost">{if(
              @feature_desired,
              do: "Request disable",
              else: "Request enable"
            )}</button>
          </:action>
        </.feature_card>
        <div id="integration-states" class="grid gap-4 md:grid-cols-2">
          <.integration_card
            :for={integration <- @integrations}
            id={"integration-#{integration.id}"}
            title={integration.title}
            scope="Branch"
            configured={integration.configured}
            desired={integration.desired}
            effective={integration.effective}
            connection_status={integration.connection_status}
            connection_summary={integration.connection_summary}
            capabilities={integration.capabilities}
            dependencies={integration.dependencies}
            issues={integration.issues}
            obligations={integration.obligations}
          >
            <:action>
              <button
                :if={integration.connection_status != :checking}
                id={"check-connection-#{integration.id}"}
                type="button"
                phx-click="check_connection"
                phx-value-id={integration.id}
                class="btn btn-ghost"
              >Check fixture connection</button>
              <button
                :if={integration.connection_status == :checking}
                id={"finish-connection-#{integration.id}"}
                type="button"
                phx-click="finish_connection_check"
                phx-value-id={integration.id}
                class="btn btn-ghost"
              >Show fixture result</button>
            </:action>
          </.integration_card>
        </div>
      </section>

      <.side_panel
        :if={@panel}
        id="gallery-panel"
        title="Quick preview"
        dirty={@panel_draft != @panel_saved}
      >
        <form id="gallery-panel-form" phx-change="panel_change" phx-submit="panel_save">
          <label for="gallery-panel-note">Quick note</label><input
            id="gallery-panel-note"
            name="note"
            value={@panel_draft}
            class="input input-bordered w-full"
          />
        </form><:actions>
          <button
            type="button"
            phx-click="panel_save"
            disabled={@panel_draft == @panel_saved}
            class="btn btn-primary"
          >Save note</button>
          <button type="button" phx-click="close_panel" class="btn btn-ghost">Close</button>
        </:actions>
      </.side_panel>
      <.live_component
        :if={@picker_open}
        module={DelivestWeb.Staff.ProductLive.ProductPicker}
        id="gallery-product-picker"
        products={@products}
        selected_ids={@picker_ids}
        mode={:multiple}
        on_save={fn ids -> send(self(), {:picker_saved, ids}) end}
        on_cancel={fn -> send(self(), :picker_cancelled) end}
      />
      <.confirm_dialog
        :if={@form_state.confirmation == :cancel}
        id="discard-dialog"
        title="Discard changes?"
        message="Branch edits will be lost."
        action="Discard branch edits"
      />
      <.confirm_dialog
        :if={@panel_confirm}
        id="panel-discard-dialog"
        title="Discard quick note?"
        message="The unsaved note will be lost."
        action="Discard note"
        stay_event="stay_panel"
        action_event="discard_panel"
      />
      <.confirm_dialog
        :if={@form_state.confirmation == :leave}
        id="leave-dialog"
        title="Unsaved changes"
        message="Branch edits will be lost if you leave."
        action="Leave without saving"
        action_event="confirm_leave"
      />
      <.confirm_dialog
        :if={@form_state.confirmation == :reload}
        id="reload-dialog"
        title="Reload latest branch?"
        message="Your unsaved edits will be lost."
        action="Reload latest"
        action_event="confirm_reload"
      />
      <.confirm_dialog
        :if={@bulk_pending}
        id="bulk-dialog"
        title="Archive selected products?"
        message={"#{ListState.selected_count(@list)} fixture products on this page will be accepted."}
        action="Archive selected products"
        stay_event="cancel_bulk"
        action_event="confirm_bulk"
      />
    </div>
    """
  end

  defp page_title("queue"), do: "Working queue"
  defp page_title("list"), do: "Products"
  defp page_title("entity"), do: "Product card"
  defp page_title("settings"), do: "Branch settings"
end
