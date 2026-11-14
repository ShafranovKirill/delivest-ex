defmodule DelivestWeb.Staff.FoundationComponents do
  @moduledoc "Reusable content components for the staff foundation gallery and future page migrations."
  use DelivestWeb, :html

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :description, :string, default: nil
  attr :scope, :string, default: nil
  slot :primary
  slot :secondary

  def workspace_header(assigns) do
    ~H"""
    <header id={@id} class="foundation-page-header flex flex-wrap items-start justify-between gap-4">
      <div class="min-w-0">
        <p :if={@scope} class="text-sm text-base-content/70">{@scope}</p>
        <h1 class="text-2xl font-semibold leading-tight break-words">{@title}</h1>
        <p :if={@description} class="mt-1 text-sm text-base-content/70">{@description}</p>
      </div>
      <div class="flex flex-wrap items-center gap-2">
        <span :for={action <- @secondary}>{render_slot(action)}</span>
        <span :for={action <- @primary}>{render_slot(action)}</span>
      </div>
    </header>
    """
  end

  attr :id, :string, required: true
  attr :items, :list, required: true
  attr :active, :string, required: true

  def section_nav(assigns) do
    ~H"""
    <nav
      id={@id}
      aria-label={gettext("Page sections")}
      class="foundation-section-nav flex gap-2 overflow-x-auto border-b border-base-300"
    >
      <.link
        :for={item <- @items}
        patch={item.path}
        aria-current={@active == item.id && "page"}
        class={[
          "shrink-0 px-3 py-2 text-sm",
          @active == item.id && "border-b-2 border-primary font-semibold"
        ]}
      >{item.label}</.link>
    </nav>
    """
  end

  attr :id, :string, required: true
  attr :form_id, :string, default: nil
  attr :query, :string, default: ""
  attr :query_name, :string, default: "q"
  attr :query_input_id, :string, default: nil
  attr :query_placeholder, :string, default: nil
  attr :reset_path, :string, required: true
  attr :event, :any, default: "filter"
  attr :target, :any, default: nil
  attr :active, :boolean, default: false
  slot :filter

  def filter_bar(assigns) do
    ~H"""
    <div id={@id} class="flex flex-wrap items-end gap-3">
      <form
        id={@form_id || "#{@id}-form"}
        phx-change={@event}
        phx-submit={@event}
        phx-target={@target}
        role="search"
        class="flex min-w-56 flex-1 flex-wrap items-end gap-3"
      >
        <div class="min-w-56 flex-1">
          <label for={@query_input_id || "#{@id}-query"} class="block text-sm font-medium">{gettext(
            "Search"
          )}</label>
          <input
            id={@query_input_id || "#{@id}-query"}
            type="search"
            name={@query_name}
            value={@query}
            placeholder={@query_placeholder}
            phx-debounce="350"
            class="input input-bordered w-full"
          />
        </div>
        {render_slot(@filter)}
        <button type="submit" class="btn btn-outline">{gettext("Apply")}</button>
      </form>
      <.link :if={@active or @query != ""} patch={@reset_path} class="btn btn-ghost">{gettext("Reset")}</.link>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :columns, :list, required: true
  attr :selected, :any, default: MapSet.new()
  attr :select_event, :any, default: "select"
  attr :target, :any, default: nil
  attr :row_id, :any, default: nil
  attr :row_label, :any, default: nil
  attr :reset_path, :string, default: nil
  attr :sort_path, :any, default: nil
  attr :page_path, :any, default: nil
  attr :per_page_path, :any, default: nil
  attr :page, :integer, default: 1
  attr :pages, :integer, default: 1
  attr :per_page, :integer, default: 25
  attr :empty_kind, :atom, default: :empty

  slot :cell do
    attr :key, :string, required: true
  end

  slot :action

  def data_table(assigns) do
    assigns =
      assign(assigns, :row_id, assigns.row_id || fn row -> "#{assigns.id}-row-#{row.id}" end)

    ~H"""
    <section id={@id} class="space-y-3">
      <.table
        id={"#{@id}-rows"}
        variant={:foundation}
        rows={@rows}
        selected={@selected}
        select_event={@select_event}
        target={@target}
        row_id={@row_id}
        row_label={@row_label}
        sort_path={@sort_path}
      >
        <:col
          :let={row}
          :for={column <- @columns}
          key={column.key}
          label={column.label}
          sort={if(column.sortable, do: column.key, else: nil)}
          numeric={column.numeric}
          secondary={column.secondary}
          field={column.field}
        >
          <%= if custom = Enum.find(@cell, &(&1.key == column.key)) do %>
            {render_slot(custom, row)}
          <% else %>
            <.link :if={Map.get(column, :link, false) and Map.get(row, :path)} navigate={row.path}>{Map.get(
              row,
              column.field
            )}</.link>
            <span :if={not Map.get(column, :link, false) or is_nil(Map.get(row, :path))}>{Map.get(
              row,
              column.field
            )}</span>
          <% end %>
        </:col>
        <:action :let={row} :for={action <- @action}>{render_slot(action, row)}</:action>
      </.table>
      <.empty_state
        :if={@rows == []}
        title={
          if(@empty_kind == :no_results,
            do: gettext("Nothing found"),
            else: gettext("No records yet")
          )
        }
      >
        <.link :if={@empty_kind == :no_results and @reset_path} patch={@reset_path}>{gettext(
          "Reset filters"
        )}</.link>
      </.empty_state>
      <nav
        :if={@page_path && @pages > 1}
        aria-label={gettext("Pagination")}
        class="flex items-center justify-end gap-2"
      >
        <.link :if={@page > 1} patch={@page_path.(@page - 1)} class="btn btn-ghost">{gettext(
          "Previous"
        )}</.link>
        <span>{@page} / {@pages}</span>
        <.link :if={@page < @pages} patch={@page_path.(@page + 1)} class="btn btn-ghost">{gettext(
          "Next"
        )}</.link>
      </nav>
      <p class="text-xs text-base-content/70">
        {gettext("%{count} rows on this page · %{per_page} per page",
          count: length(@rows),
          per_page: @per_page
        )}
      </p>
      <nav :if={@per_page_path} aria-label={gettext("Page size")} class="flex gap-2">
        <.link
          :for={size <- [25, 50, 100]}
          patch={@per_page_path.(size)}
          aria-current={@per_page == size && "page"}
          class="btn btn-ghost"
        >{size}</.link>
      </nav>
    </section>
    """
  end

  attr :id, :string, required: true
  attr :count, :integer, required: true
  slot :inner_block

  def bulk_action_bar(assigns) do
    ~H"""
    <div
      :if={@count > 0}
      id={@id}
      role="status"
      class="flex flex-wrap items-center gap-3 rounded-box border border-base-300 bg-base-100 p-3"
    >
      <strong>{gettext("Selected %{count} on this page", count: @count)}</strong>
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :description, :string, default: nil
  slot :inner_block, required: true

  def form_section(assigns) do
    ~H"""
    <section id={@id} class="foundation-form-section border-t border-base-300 py-6">
      <h2 class="text-lg font-semibold">{@title}</h2>
      <p :if={@description} class="text-sm text-base-content/70">{@description}</p>
      <div class="mt-4 space-y-4">{render_slot(@inner_block)}</div>
    </section>
    """
  end

  attr :id, :string, required: true
  attr :state, :any, required: true
  attr :cancel_event, :any, default: "cancel"
  attr :target, :any, default: nil
  slot :recovery

  def form_actions(assigns) do
    ~H"""
    <div id={@id} class="flex flex-wrap items-center gap-2 border-t border-base-300 py-4">
      <button
        type="submit"
        class="btn btn-primary"
        disabled={
          not DelivestWeb.Staff.Foundation.FormState.dirty?(@state) or
            not @state.writable? or @state.status in [:pending, :conflict]
        }
      >{gettext("Save changes")}</button>
      <button
        type="button"
        phx-click={@cancel_event}
        phx-target={@target}
        class="btn btn-ghost"
        disabled={@state.status == :pending}
      >{gettext("Cancel changes")}</button>
      <span :if={@state.status == :pending} role="status">{gettext("Saving…")}</span>
      <span :if={@state.status == :success} role="status">{gettext("Saved")}</span>
      <span :if={@state.status == :error} role="alert">{gettext(
        "Could not save. Review the error and retry."
      )}</span>
      <span :if={@state.status == :conflict} role="alert">{gettext(
        "Changes conflict. Review the latest data before retrying."
      )}</span>
      <span :if={not @state.writable?} role="status">{gettext("View only")}</span>
      <div :if={@state.status == :conflict and @recovery != []} class="flex gap-2">
        {render_slot(@recovery)}
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :errors, :map, required: true
  attr :form_name, :string, default: nil

  def error_summary(assigns) do
    ~H"""
    <div :if={map_size(@errors) > 0} id={@id} role="alert" class="alert alert-error">
      <p>{gettext("Check these fields:")}</p>
      <ul>
        <li :for={{field, message} <- @errors}>
          <a href={"##{if @form_name, do: "#{@form_name}_#{field}", else: field}"}>{message}</a>
        </li>
      </ul>
    </div>
    """
  end

  @doc "Translated field errors for the shared summary; nested embeds keep their input path."
  def changeset_errors(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(&DelivestWeb.CoreComponents.translate_error/1)
    |> flatten_errors([], %{})
  end

  def changeset_errors(_), do: %{}

  defp flatten_errors(errors, path, acc) when is_map(errors) do
    Enum.reduce(errors, acc, fn {field, value}, acc ->
      flatten_errors(value, path ++ [to_string(field)], acc)
    end)
  end

  defp flatten_errors(errors, path, acc) when is_list(errors) do
    if Enum.all?(errors, &is_binary/1) do
      Map.put(acc, Enum.join(path, "_"), Enum.join(errors, ", "))
    else
      errors
      |> Enum.with_index()
      |> Enum.reduce(acc, fn {value, index}, acc ->
        flatten_errors(value, path ++ [to_string(index)], acc)
      end)
    end
  end

  defp flatten_errors(_errors, _path, acc), do: acc

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :tone, :atom, default: :neutral

  def status_badge(assigns) do
    ~H"""
    <span
      id={@id}
      class={[
        "badge",
        @tone == :success && "badge-success",
        @tone == :warning && "badge-warning",
        @tone == :error && "badge-error"
      ]}
    >{@label}</span>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :scope, :string, required: true
  attr :configured, :boolean, required: true
  attr :desired, :boolean, required: true
  attr :effective, :boolean, required: true
  attr :dependencies, :list, default: []
  attr :issues, :list, default: []
  attr :obligations, :list, default: []
  attr :capabilities, :list, default: []
  attr :connection_status, :atom, default: :unknown
  attr :connection_summary, :string, default: nil
  slot :action

  def integration_card(assigns) do
    ~H"""
    <article id={@id} class="rounded-box border border-base-300 bg-base-100 p-5 space-y-2">
      <h2 class="text-lg font-semibold">{@title}</h2>
      <p class="text-sm">{@scope}</p>
      <dl class="grid grid-cols-2 gap-2 text-sm">
        <dt>{gettext("Configured")}</dt><dd>{yes_no(@configured)}</dd>
        <dt>{gettext("Desired")}</dt><dd>{yes_no(@desired)}</dd>
        <dt>{gettext("Effective")}</dt><dd>
          <.status_badge
            id={"#{@id}-effective"}
            label={yes_no(@effective)}
            tone={if @effective, do: :success, else: :warning}
          />
        </dd>
        <dt>{gettext("Connection")}</dt><dd>
          <.status_badge
            id={"#{@id}-connection"}
            label={connection_label(@connection_status)}
            tone={connection_tone(@connection_status)}
          />
        </dd>
      </dl>
      <p :if={@connection_summary} class="text-sm">{@connection_summary}</p>
      <div :if={@capabilities != []}>
        <h3 class="text-sm font-semibold">{gettext("Capabilities")}</h3>
        <ul class="space-y-1 text-sm">
          <li :for={capability <- @capabilities}>
            {capability.label}: {capability.state}
          </li>
        </ul>
      </div>
      <p>{gettext("Dependencies")}: {list_text(@dependencies)}</p>
      <p>{gettext("Issues")}: {list_text(@issues)}</p>
      <p>{gettext("Obligations")}: {list_text(@obligations)}</p>
      <div :if={@action != []} class="flex flex-wrap gap-2">{render_slot(@action)}</div>
    </article>
    """
  end

  defp yes_no(true), do: gettext("Yes")
  defp yes_no(false), do: gettext("No")
  defp connection_label(:unknown), do: gettext("Unknown")
  defp connection_label(:checking), do: gettext("Checking")
  defp connection_label(:ok), do: gettext("Connected")
  defp connection_label(:error), do: gettext("Connection error")
  defp connection_label(:stale), do: gettext("Check is stale")
  defp connection_tone(:ok), do: :success
  defp connection_tone(:error), do: :error
  defp connection_tone(_), do: :warning
  defp list_text([]), do: gettext("None")
  defp list_text(items), do: Enum.join(items, ", ")

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :message, :string, required: true
  attr :action, :string, required: true
  attr :pending, :boolean, default: false
  attr :stay_event, :string, default: "stay"
  attr :action_event, :string, default: "discard"
  attr :target, :any, default: nil

  def confirm_dialog(assigns) do
    ~H"""
    <div
      id={@id}
      role="dialog"
      aria-modal="true"
      aria-labelledby={"#{@id}-title"}
      class="foundation-modal fixed inset-0 z-50 grid place-items-center bg-black/50 p-4"
      phx-hook="FoundationDialog"
      data-dirty="false"
      data-close-event={@stay_event}
      data-target={not is_nil(@target) && "component"}
      data-pending={to_string(@pending)}
    >
      <div class="w-full max-w-lg rounded-box bg-base-100 p-6 shadow-xl">
        <h2 id={"#{@id}-title"} class="text-lg font-semibold">{@title}</h2><p class="my-4">
          {@message}
        </p>
        <div class="flex justify-end gap-2">
          <button type="button" phx-click={@stay_event} phx-target={@target} class="btn btn-ghost">{gettext(
            "Stay"
          )}</button><button
            type="button"
            phx-click={@action_event}
            phx-target={@target}
            disabled={@pending}
            class="btn btn-error"
          >{@action}</button>
        </div>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :dirty, :boolean, default: false
  attr :close_event, :string, default: "close_panel"
  attr :target, :any, default: nil
  slot :inner_block, required: true
  slot :actions

  def side_panel(assigns) do
    ~H"""
    <aside
      id={@id}
      role="dialog"
      aria-modal="true"
      aria-label={@title}
      phx-hook="FoundationDialog"
      data-dirty={to_string(@dirty)}
      data-close-event={@close_event}
      data-target={not is_nil(@target) && "component"}
      class="foundation-panel fixed inset-y-0 right-0 z-50 flex w-full max-w-lg flex-col border-l border-base-300 bg-base-100 shadow-xl"
    >
      <header class="flex items-center justify-between border-b border-base-300 p-4">
        <h2 class="text-lg font-semibold">{@title}</h2><button
          type="button"
          phx-click={@close_event}
          phx-target={@target}
          aria-label={gettext("Close panel")}
          class="btn btn-ghost btn-square"
        >×</button>
      </header>
      <div class="flex-1 overflow-y-auto p-4">{render_slot(@inner_block)}</div>
      <footer class="border-t border-base-300 p-4">{render_slot(@actions)}</footer>
    </aside>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :kind, :atom, required: true

  def state_notice(assigns) do
    ~H"""
    <div
      id={@id}
      role={if @kind == :error, do: "alert", else: "status"}
      class="rounded-box border border-base-300 p-6 text-center"
    >
      {@title}
    </div>
    """
  end

  @doc "Column display only. Preferences are per employee and list in browser storage; URL filters stay server owned."
  attr :id, :string, required: true
  attr :staff_id, :string, required: true
  attr :list_id, :string, required: true
  attr :table_id, :string, required: true
  attr :columns, :list, required: true

  def column_chooser(assigns) do
    ~H"""
    <fieldset
      id={@id}
      phx-hook="FoundationColumns"
      phx-update="ignore"
      data-staff-id={@staff_id}
      data-list-id={@list_id}
      data-table-id={@table_id}
      class="flex flex-wrap gap-3 text-sm"
    >
      <legend class="font-medium">{gettext("Visible columns")}</legend>
      <label :for={column <- @columns} class="flex items-center gap-1">
        <input
          type="checkbox"
          data-column={column.key}
          checked={!column.secondary}
          disabled={Map.get(column, :required, false)}
        />{column.label}
      </label>
    </fieldset>
    """
  end

  @doc "Only pass server-authorized destinations in `options`; this component never grants access."
  attr :id, :string, required: true
  attr :scope, :string, required: true
  attr :options, :list, required: true
  attr :query, :string, default: ""
  attr :search_event, :any, default: "scope_search"
  attr :target, :any, default: nil

  def scope_switcher(assigns) do
    ~H"""
    <div id={@id} class="flex flex-wrap items-center gap-2" aria-label={gettext("Data scope")}>
      <span class="text-sm">{gettext("Scope")}: {@scope}</span>
      <details>
        <summary class="btn btn-ghost">{gettext("Switch scope")}</summary>
        <div class="rounded-box border border-base-300 bg-base-100 p-2 shadow-lg">
          <form
            id={"#{@id}-search-form"}
            phx-change={@search_event}
            phx-submit={@search_event}
            phx-target={@target}
          >
            <label for={"#{@id}-query"} class="sr-only">{gettext("Search available branches")}</label>
            <input
              id={"#{@id}-query"}
              type="search"
              name="q"
              value={@query}
              phx-debounce="300"
              class="input input-bordered w-full"
            />
          </form>
          <ul>
            <li :for={option <- @options}>
              <.link patch={option.path} aria-current={option.label == @scope && "page"}>{option.label}</.link>
            </li>
          </ul>
          <p :if={@options == []} role="status">{gettext("No available branches found")}</p>
        </div>
      </details>
    </div>
    """
  end

  @doc "The caller provides desired/effective state computed by the domain gateway."
  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :desired, :boolean, required: true
  attr :effective, :boolean, required: true
  attr :reason, :string, default: nil
  slot :action

  def feature_card(assigns) do
    ~H"""
    <article id={@id} class="rounded-box border border-base-300 bg-base-100 p-4">
      <h2 class="font-semibold">{@title}</h2>
      <p>{gettext("Desired")}: {yes_no(@desired)} · {gettext("Effective")}: {yes_no(@effective)}</p>
      <p :if={@reason} role="status">{@reason}</p>
      {render_slot(@action)}
    </article>
    """
  end

  @doc "Subject field adapter: validation and persistence belong to the existing changeset."
  attr :field, Phoenix.HTML.FormField, required: true
  attr :label, :string, required: true
  attr :kind, :atom, required: true

  def domain_field(assigns) do
    ~H"""
    <.input
      :if={@kind == :money}
      field={@field}
      label={@label}
      type="text"
      inputmode="decimal"
      value={Delivest.Money.input(@field.value)}
    />
    <.input :if={@kind == :phone} field={@field} label={@label} type="tel" inputmode="tel" />
    <.input
      :if={@kind == :address}
      field={@field}
      label={@label}
      type="text"
      autocomplete="street-address"
    />
    """
  end

  @doc "Branch address adapter delegates to the existing location field group; caller owns map/suggestion events."
  attr :form, Phoenix.HTML.Form, required: true
  attr :map, :boolean, default: false
  attr :suggestions, :list, default: []
  attr :target, :any, default: nil

  def address_field(assigns) do
    ~H"""
    <DelivestWeb.Staff.BranchLive.LocationFields.location_fields
      form={@form}
      map={@map}
      suggestions={@suggestions}
      target={@target}
    />
    """
  end

  @doc "Schedule adapter delegates the established branch hours editor and its server validation."
  attr :id, :string, required: true
  attr :working_hours, :map, required: true

  def schedule_editor(assigns) do
    ~H"""
    <.live_component
      module={DelivestWeb.Staff.BranchLive.WorkingHoursComponent}
      id={@id}
      working_hours={@working_hours}
    />
    """
  end
end
