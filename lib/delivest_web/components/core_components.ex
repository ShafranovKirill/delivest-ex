defmodule DelivestWeb.CoreComponents do
  @moduledoc """
  Provides core UI components.

  At first glance, this module may seem daunting, but its goal is to provide
  core building blocks for your application, such as tables, forms, and
  inputs. The components consist mostly of markup and are well-documented
  with doc strings and declarative assigns. You may customize and style
  them in any way you want, based on your application growth and needs.

  The foundation for styling is Tailwind CSS, a utility-first CSS framework,
  augmented with daisyUI, a Tailwind CSS plugin that provides UI components
  and themes. Here are useful references:

    * [daisyUI](https://daisyui.com/docs/intro/) - a good place to get
      started and see the available components.

    * [Tailwind CSS](https://tailwindcss.com) - the foundational framework
      we build on. You will use it for layout, sizing, flexbox, grid, and
      spacing.

    * [Heroicons](https://heroicons.com) - see `icon/1` for usage.

    * [Phoenix.Component](https://phoenix-live-view.hexdocs.pm/Phoenix.Component.html) -
      the component system used by Phoenix. Some components, such as `<.link>`
      and `<.form>`, are defined there.

  """
  use Phoenix.Component
  use Gettext, backend: DelivestWeb.Gettext

  alias Phoenix.LiveView.JS

  @doc """
  Renders flash notices.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash
        id="welcome-back"
        kind={:info}
        phx-mounted={show("#welcome-back") |> JS.remove_attribute("hidden")}
        hidden
      >
        Welcome Back!
      </.flash>
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role="alert"
      class="toast toast-top toast-end z-50"
      {@rest}
    >
      <div class={[
        "alert w-80 sm:w-96 max-w-80 sm:max-w-96 text-wrap",
        @kind == :info && "alert-info",
        @kind == :error && "alert-error"
      ]}>
        <.icon :if={@kind == :info} name="hero-information-circle" class="size-5 shrink-0" />
        <.icon :if={@kind == :error} name="hero-exclamation-circle" class="size-5 shrink-0" />
        <div>
          <p :if={@title} class="font-semibold">{@title}</p>
          <p>{msg}</p>
        </div>
        <div class="flex-1" />
        <button type="button" class="group self-start cursor-pointer" aria-label={gettext("close")}>
          <.icon name="hero-x-mark" class="size-5 opacity-40 group-hover:opacity-70" />
        </button>
      </div>
    </div>
    """
  end

  @doc """
  Renders a button with navigation support.

  ## Examples

      <.button>Send!</.button>
      <.button phx-click="go" variant="primary">Send!</.button>
      <.button navigate={~p"/"}>Home</.button>
  """
  attr :rest, :global, include: ~w(href navigate patch method download name value disabled form)
  attr :class, :any
  attr :variant, :string, values: ~w(primary)
  slot :inner_block, required: true

  def button(%{rest: rest} = assigns) do
    variants = %{"primary" => "btn-primary", nil => "btn-outline"}

    assigns =
      assign_new(assigns, :class, fn ->
        ["btn", Map.fetch!(variants, assigns[:variant])]
      end)

    if rest[:href] || rest[:navigate] || rest[:patch] do
      ~H"""
      <.link class={@class} {@rest}>
        {render_slot(@inner_block)}
      </.link>
      """
    else
      ~H"""
      <button class={@class} {@rest}>
        {render_slot(@inner_block)}
      </button>
      """
    end
  end

  @doc """
  Renders an input with label and error messages.

  A `Phoenix.HTML.FormField` may be passed as argument,
  which is used to retrieve the input name, id, and values.
  Otherwise all attributes may be passed explicitly.

  ## Types

  This function accepts all HTML input types, considering that:

    * You may also set `type="select"` to render a `<select>` tag

    * `type="checkbox"` is used exclusively to render boolean values

    * For live file uploads, see `Phoenix.Component.live_file_input/1`

  See https://developer.mozilla.org/en-US/docs/Web/HTML/Element/input
  for more information. Unsupported types, such as radio, are best
  written directly in your templates.


  ## Select type

  When using `type="select"`, you must pass the `options` and optionally
  a `value` to mark which option should be preselected.

  For more information on what kind of data can be passed to `options` see
  [`options_for_select`](https://hexdocs.pm/phoenix_html/Phoenix.HTML.Form.html#options_for_select/2).
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file month number password
               search select tel text textarea time url week hidden)

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"
  attr :class, :any, default: nil, doc: "the input class to use over defaults"
  attr :error_class, :any, default: nil, doc: "the input error class to use over defaults"

  attr :rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "hidden"} = assigns) do
    ~H"""
    <input type="hidden" id={@id} name={@name} value={@value} {@rest} />
    """
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Phoenix.HTML.Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <fieldset class="fieldset mb-2 w-full">
      <label class="label cursor-pointer justify-start gap-3">
        <input
          type="hidden"
          name={@name}
          value="false"
          disabled={@rest[:disabled]}
          form={@rest[:form]}
        />
        <input
          type="checkbox"
          id={@id}
          name={@name}
          value="true"
          checked={@checked}
          class={[@class || "checkbox checkbox-primary", @errors != [] && "checkbox-error!"]}
          {@rest}
        />
        <span class="label-text font-bold">{@label}</span>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </fieldset>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <fieldset class="fieldset mb-2 w-full">
      <label :if={@label} for={@id} class="label">
        <span class="label-text font-bold">{@label}</span>
      </label>
      <select
        id={@id}
        name={@name}
        class={[
          "select w-full",
          @errors != [] && "select-error border-error!",
          @class,
          @multiple && "h-auto py-2"
        ]}
        multiple={@multiple}
        {@rest}
      >
        <option :if={@prompt} value="" disabled selected={@value in [nil, ""]}>
          {@prompt}
        </option>
        {Phoenix.HTML.Form.options_for_select(@options, @value)}
      </select>
      <.error :for={msg <- @errors}>{msg}</.error>
    </fieldset>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <fieldset class="fieldset mb-2 w-full">
      <label :if={@label} for={@id} class="label">
        <span class="label-text font-bold">{@label}</span>
      </label>
      <textarea
        id={@id}
        name={@name}
        class={[
          @class || "textarea w-full",
          @errors != [] && (@error_class || "textarea-error border-error!")
        ]}
        {@rest}
      >{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
      <.error :for={msg <- @errors}>{msg}</.error>
    </fieldset>
    """
  end

  # All other inputs text, datetime-local, url, password, etc. are handled here...
  def input(assigns) do
    ~H"""
    <fieldset class="fieldset mb-2 w-full">
      <label :if={@label} for={@id} class="label">
        <span class="label-text font-bold">{@label}</span>
      </label>
      <input
        type={@type}
        name={@name}
        id={@id}
        value={Phoenix.HTML.Form.normalize_value(@type, @value)}
        class={[
          @class || "input w-full",
          @errors != [] && (@error_class || "input-error border-error!")
        ]}
        {@rest}
      />
      <.error :for={msg <- @errors}>{msg}</.error>
    </fieldset>
    """
  end

  # Helper used by inputs to generate form errors
  defp error(assigns) do
    ~H"""
    <p class="mt-1.5 flex gap-2 items-center text-sm text-error">
      <.icon name="hero-exclamation-circle" class="size-5" />
      {render_slot(@inner_block)}
    </p>
    """
  end

  @doc """
  Renders a header with title.
  """
  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  def header(assigns) do
    ~H"""
    <header class={[@actions != [] && "flex items-center justify-between gap-6", "pb-4"]}>
      <div>
        <h1 class="text-lg font-semibold leading-8">
          {render_slot(@inner_block)}
        </h1>
        <p :if={@subtitle != []} class="text-sm text-base-content/70">
          {render_slot(@subtitle)}
        </p>
      </div>
      <div class="flex-none">{render_slot(@actions)}</div>
    </header>
    """
  end

  @doc """
  Renders the staff page title, navigation, and actions in the shared header.
  """
  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  attr :back, :string, default: nil
  attr :title_in_header, :boolean, default: true
  attr :navigation_label, :string, default: nil
  slot :navigation
  slot :actions

  def page_header(assigns) do
    ~H"""
    <div id="staff-page-header" class="w-full min-w-0">
      <div class="staff-page-header-two-rows flex h-full w-full min-w-0 items-center gap-1.5">
        <.link
          :if={@back}
          navigate={@back}
          class="btn btn-ghost btn-xs btn-square shrink-0"
          title={gettext("Back")}
          aria-label={gettext("Back")}
        >
          <.icon name="hero-arrow-left" class="size-4" />
        </.link>
        <h1
          title={@title}
          class="staff-page-header-title min-w-0 text-2xl font-semibold text-base-content"
        >
          {@title}
        </h1>
        <.header_navigation :if={@navigation != []} label={@navigation_label}>
          {render_slot(@navigation)}
        </.header_navigation>
      </div>
      <div
        :if={@actions != []}
        id="staff-header-actions"
        phx-hook="HeaderScroll"
        class="staff-header-actions staff-header-scroll"
      >
        <div id="staff-header-actions-scroll" class="staff-header-actions-scroll" data-scroll-viewport>
          <div
            id="staff-page-header-actions"
            class="staff-page-header-actions flex w-max min-w-full items-center gap-2 whitespace-nowrap"
          >
            {render_slot(@actions)}
          </div>
        </div>
      </div>
      <p :if={@subtitle} class="mt-1 text-sm text-base-content/70">{@subtitle}</p>
    </div>
    """
  end

  attr :label, :string, default: nil
  slot :inner_block, required: true

  def header_navigation(assigns) do
    ~H"""
    <div
      id="staff-page-header-navigation-scroll"
      phx-hook="HeaderScroll"
      class="staff-header-scroll min-w-0 flex-1"
    >
      <nav
        id="staff-page-header-navigation"
        phx-hook="ActiveSectionNav"
        data-scroll-viewport
        class="staff-page-header-navigation min-w-0 flex-1 overflow-x-auto"
        aria-label={@label || gettext("Page sections")}
      >
        {render_slot(@inner_block)}
      </nav>
    </div>
    """
  end

  attr :icon, :string, default: "hero-inbox"
  attr :title, :string, required: true
  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block

  def empty_state(assigns) do
    ~H"""
    <div
      class={[
        "flex flex-col items-center justify-center gap-2 py-12 text-center text-base-content/50",
        @class
      ]}
      {@rest}
    >
      <.icon name={@icon} class="size-10 stroke-1" />
      <p class="text-sm font-medium">{@title}</p>
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :count, :integer, required: true
  attr :form, :string, required: true
  attr :on_clear, :any, required: true
  slot :inner_block, required: true

  def selection_bar(assigns) do
    ~H"""
    <div :if={@count > 0} id={"#{@form}-bar"} class="sticky bottom-4 z-20 flex justify-center">
      <div class="flex items-center gap-2 rounded-box border border-base-300 bg-base-100 py-2 pl-4 pr-2 shadow-lg">
        <span class="whitespace-nowrap text-sm font-medium">
          {gettext("Selected: %{count}", count: @count)}
        </span>
        {render_slot(@inner_block)}
        <button
          type="reset"
          form={@form}
          phx-click={@on_clear}
          class="btn btn-ghost btn-sm btn-square"
          title={gettext("Clear selection")}
        >
          <.icon name="hero-x-mark" class="size-4" />
        </button>
      </div>
    </div>
    """
  end

  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def card(assigns) do
    ~H"""
    <div class={["rounded-box border border-base-300 bg-base-100", @class]} {@rest}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc """
  Renders a table with generic styling.

  ## Examples

      <.table id="users" rows={@users}>
        <:col :let={user} label="id">{user.id}</:col>
        <:col :let={user} label="username">{user.username}</:col>
      </.table>
  """
  attr :meta, Flop.Meta, default: nil, doc: "Flop meta for sorting"
  attr :path_fn, :any, default: nil, doc: "Function that takes a map of params and returns a URL"
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :variant, :atom, default: :legacy
  attr :selected, :any, default: MapSet.new()
  attr :select_event, :any, default: "select"
  attr :target, :any, default: nil
  attr :row_label, :any, default: nil
  attr :sort_path, :any, default: nil
  attr :row_id, :any, default: nil, doc: "the function for generating the row id"
  attr :row_click, :any, default: nil, doc: "the function for handling phx-click on each row"
  attr :staff_id, :string, default: nil, doc: "Employee ID for column preferences"
  attr :list_id, :string, default: nil, doc: "Stable list key for column preferences"
  attr :empty_title, :string, default: nil
  attr :sticky_leading, :boolean, default: false

  attr :row_item, :any,
    default: &Function.identity/1,
    doc: "the function for mapping each row before calling the :col and :action slots"

  slot :col, required: true do
    attr :label, :string
    attr :sort, :string, doc: "Field name for Flop sorting"
    attr :secondary, :boolean, doc: "Hidden on phones"
    attr :key, :string, doc: "Foundation column preference key"
    attr :numeric, :boolean, doc: "Foundation right alignment"
    attr :field, :atom, doc: "Plain value in the foundation mobile detail row"
  end

  slot :action, doc: "the slot for showing user actions in the last table column"

  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <div class="space-y-2">
      <details
        :if={@variant != :foundation and Enum.any?(@col, & &1[:secondary])}
        class="staff-column-chooser text-sm"
      >
        <summary class="btn btn-ghost btn-sm">{gettext("Visible columns")}</summary>
        <fieldset
          id={"#{@id}-columns"}
          phx-hook="FoundationColumns"
          phx-update="ignore"
          data-staff-id={@staff_id}
          data-list-id={@list_id || @id}
          data-table-id={"#{@id}-table"}
          class="flex flex-wrap gap-3 p-2"
        >
          <label
            :for={{col, index} <- Enum.with_index(@col)}
            :if={col[:label] not in [nil, ""]}
            class="flex items-center gap-1"
          >
            <input
              type="checkbox"
              data-column={column_key(col, index)}
              checked={!col[:secondary]}
              disabled={!col[:secondary]}
            />{col[:label]}
          </label>
        </fieldset>
      </details>
      <div class="overflow-x-auto overflow-y-visible sm:border sm:border-base-300 rounded-box">
        <table
          id={"#{@id}-table"}
          class={[
            "table table-zebra table-sm max-sm:block",
            @sticky_leading && "table-leading-actions"
          ]}
          aria-label={gettext("Results")}
        >
          <thead class="max-sm:hidden">
            <tr>
              <th :if={@variant == :foundation} scope="col">
                <span class="sr-only">{gettext("Select")}</span>
              </th>
              <th
                :for={{col, index} <- Enum.with_index(@col)}
                scope="col"
                data-column={column_key(col, index)}
                class={[
                  col[:numeric] && "text-right",
                  col[:secondary] && "foundation-column-secondary"
                ]}
              >
                <%= if col[:sort] && @sort_path do %>
                  <.link patch={@sort_path.(col[:sort])} class="hover:text-primary">{col[:label]}</.link>
                <% else %>
                  <%= if col[:sort] && @meta && @path_fn do %>
                    <% current_sort? =
                      @meta.flop.order_by |> List.wrap() |> List.first() |> to_string() == col[:sort] %>
                    <% direction =
                      if current_sort? and
                           @meta.flop.order_directions |> List.wrap() |> List.first() == :asc,
                         do: "desc",
                         else: "asc" %>
                    <.link
                      patch={
                        @path_fn.(%{"order_by" => [col[:sort]], "order_directions" => [direction]})
                      }
                      class="flex items-center gap-1 hover:text-primary transition-colors group select-none"
                    >
                      {col[:label]}
                      <.icon
                        :if={current_sort? && direction == "desc"}
                        name="hero-chevron-up"
                        class="size-4"
                      />
                      <.icon
                        :if={current_sort? && direction == "asc"}
                        name="hero-chevron-down"
                        class="size-4"
                      />
                      <.icon
                        :if={!current_sort?}
                        name="hero-chevron-up-down"
                        class="size-4 opacity-0 group-hover:opacity-50 transition-opacity"
                      />
                    </.link>
                  <% else %>
                    {col[:label]}
                  <% end %>
                <% end %>
              </th>
              <th :if={@action != []}>
                <span class="sr-only">{gettext("Actions")}</span>
              </th>
            </tr>
          </thead>
          <tbody
            id={@id}
            phx-update={is_struct(@rows, Phoenix.LiveView.LiveStream) && "stream"}
            class="max-sm:block max-sm:space-y-2"
          >
            <tr
              :for={row <- @rows}
              id={@row_id && @row_id.(row)}
              class="max-sm:block max-sm:rounded-box max-sm:border max-sm:border-base-300 max-sm:bg-base-100! max-sm:px-1 max-sm:py-2"
            >
              <td :if={@variant == :foundation} class="max-sm:block">
                <input
                  type="checkbox"
                  phx-click={@select_event}
                  phx-target={@target}
                  phx-value-id={row.id}
                  checked={MapSet.member?(@selected, row.id)}
                  aria-label={
                    gettext("Select %{name}",
                      name:
                        if(@row_label,
                          do: @row_label.(row),
                          else: Map.get(row, :name, to_string(row.id))
                        )
                    )
                  }
                />
              </td>
              <td
                :for={{col, index} <- Enum.with_index(@col)}
                phx-click={@row_click && @row_click.(row)}
                data-label={col[:label]}
                data-column={column_key(col, index)}
                class={[
                  "max-sm:flex max-sm:items-center max-sm:justify-between max-sm:gap-3 max-sm:py-1.5 max-sm:text-right",
                  "max-sm:before:content-[attr(data-label)] max-sm:before:text-xs max-sm:before:text-base-content/50 max-sm:before:text-left",
                  col[:secondary] && "foundation-column-secondary",
                  col[:numeric] && "text-right",
                  @row_click && "hover:cursor-pointer"
                ]}
              >
                {render_slot(col, @row_item.(row))}
              </td>
              <td :if={Enum.any?(@col, & &1[:secondary])} class="sm:hidden max-sm:block max-sm:py-1">
                <details class="staff-row-details">
                  <summary class="text-xs font-medium">{gettext("More details")}</summary>
                </details>
              </td>
              <td :if={@action != []} class="w-0 font-semibold max-sm:block max-sm:w-auto max-sm:pt-2">
                <div class="flex gap-4 max-sm:justify-end">
                  <%= for action <- @action do %>
                    {render_slot(action, @row_item.(row))}
                  <% end %>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <.empty_state
        :if={@empty_title && ((@meta && @meta.total_count == 0) || @rows == [])}
        title={@empty_title}
      />
    </div>
    """
  end

  defp column_key(col, index), do: col[:key] || col[:sort] || "column-#{index}"

  @doc """
  Renders a data list.

  ## Examples

      <.list>
        <:item title="Title">{@post.title}</:item>
        <:item title="Views">{@post.views}</:item>
      </.list>
  """
  slot :item, required: true do
    attr :title, :string, required: true
  end

  def list(assigns) do
    ~H"""
    <ul class="list">
      <li :for={item <- @item} class="list-row">
        <div class="list-col-grow">
          <div class="font-bold">{item.title}</div>
          <div>{render_slot(item)}</div>
        </div>
      </li>
    </ul>
    """
  end

  @doc """
  Renders a slide-over (drawer) for forms.
  """
  attr :id, :string, required: true
  attr :show, :boolean, default: false
  attr :title, :string, required: true
  attr :on_close, JS, required: true
  attr :wide, :boolean, default: false
  slot :inner_block, required: true

  def slide_over(assigns) do
    ~H"""
    <div
      class={["drawer drawer-end fixed inset-0 z-100", !@show && "hidden"]}
      style="pointer-events: none;"
    >
      <input
        id={"#{@id}-toggle"}
        type="checkbox"
        class="drawer-toggle"
        checked={@show}
        aria-hidden="true"
      />
      <div class="drawer-side" style="pointer-events: auto;">
        <label for={"#{@id}-toggle"} class="drawer-overlay" phx-click={@on_close}></label>
        <div class={[
          "bg-base-100 text-base-content h-dvh w-full p-0 flex flex-col border-l border-base-300",
          if(@wide, do: "max-w-2xl", else: "max-w-md")
        ]}>
          <div class="p-6 border-b border-base-300 flex items-center justify-between shrink-0">
            <h2 class="text-xl font-display font-bold">{@title}</h2>
            <button type="button" class="btn btn-ghost btn-square btn-sm" phx-click={@on_close}>
              <.icon name="hero-x-mark" class="size-5" />
            </button>
          </div>
          <div class="flex-1 overflow-y-auto p-6">
            {render_slot(@inner_block)}
          </div>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders a DaisyUI modal dynamically using LiveView state.
  """
  attr :id, :string, required: true
  attr :show, :boolean, default: false
  attr :title, :string, default: nil
  attr :description, :string, default: nil
  attr :on_cancel, JS, default: %JS{}
  attr :on_confirm, JS, default: nil
  attr :confirm_label, :string, default: "Confirm"
  attr :danger, :boolean, default: false
  slot :inner_block

  def modal(assigns) do
    ~H"""
    <div
      id={@id}
      class={["modal", @show && "modal-open"]}
      phx-window-keydown={@show && @on_cancel}
      phx-key="escape"
    >
      <div class="modal-box border border-base-300">
        <h3 :if={@title} class="font-bold text-lg">{@title}</h3>
        <p :if={@description} class="py-4 text-base-content/70">{@description}</p>

        {render_slot(@inner_block)}

        <div :if={@on_confirm} class="modal-action">
          <button
            type="button"
            class="btn btn-outline btn-sm"
            phx-click={@on_cancel}
          >
            {gettext("Cancel")}
          </button>

          <button
            type="button"
            class={["btn btn-sm", @danger && "btn-error", !@danger && "btn-primary"]}
            phx-click={@on_confirm}
          >
            {@confirm_label}
          </button>
        </div>
      </div>

      <div class="modal-backdrop bg-black/50" phx-click={@on_cancel}>
        <button type="button" class="cursor-default" aria-label={gettext("close")}></button>
      </div>
    </div>
    """
  end

  @doc """
  Renders pagination and page size selector using Flop.Meta.
  """
  attr :meta, Flop.Meta, required: true
  attr :id, :string, default: "page-size-form"
  attr :page_sizes, :list, default: [10, 20, 50, 100]

  attr :path_fn, :any,
    required: true,
    doc: "Function that takes a map of params and returns a URL"

  def pagination(assigns) do
    page_sizes =
      if is_integer(assigns.meta.page_size) and assigns.meta.page_size > 0 do
        [assigns.meta.page_size | assigns.page_sizes] |> Enum.uniq() |> Enum.sort()
      else
        assigns.page_sizes
      end

    assigns = assign(assigns, :page_sizes, page_sizes)

    ~H"""
    <div class="flex flex-col sm:flex-row items-center justify-between w-full gap-4 mt-4">
      <div class="flex items-center gap-2">
        <span class="text-sm text-base-content/60">{gettext("Show")}</span>
        <form id={@id} phx-change="update_page_size">
          <select name="page_size" class="select select-sm">
            <%= for size <- @page_sizes do %>
              <option value={size} selected={@meta.page_size == size}>{size}</option>
            <% end %>
          </select>
        </form>
      </div>

      <div :if={@meta.total_pages > 1} class="join">
        <.link
          patch={@path_fn.(%{"page" => @meta.current_page - 1})}
          class={[
            "join-item btn btn-sm btn-outline",
            @meta.current_page <= 1 && "pointer-events-none opacity-50"
          ]}
          tabindex={if @meta.current_page <= 1, do: -1, else: 0}
        >
          «
        </.link>
        <button class="join-item btn btn-sm pointer-events-none btn-outline">
          {gettext("Page %{current} of %{total}",
            current: @meta.current_page,
            total: @meta.total_pages
          )}
        </button>
        <.link
          patch={@path_fn.(%{"page" => @meta.current_page + 1})}
          class={[
            "join-item btn btn-sm btn-outline",
            @meta.current_page >= @meta.total_pages && "pointer-events-none opacity-50"
          ]}
          tabindex={if @meta.current_page >= @meta.total_pages, do: -1, else: 0}
        >
          »
        </.link>
      </div>
    </div>
    """
  end

  @doc """
  Renders a [Heroicon](https://heroicons.com).

  Heroicons come in three styles – outline, solid, and mini.
  By default, the outline style is used, but solid and mini may
  be applied by using the `-solid` and `-mini` suffix.

  You can customize the size and colors of the icons by setting
  width, height, and background color classes.

  Icons are extracted from the `deps/heroicons` directory and bundled within
  your compiled app.css by the plugin in `assets/vendor/heroicons.js`.

  ## Examples

      <.icon name="hero-x-mark" />
      <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
  """
  attr :name, :string, required: true
  attr :class, :any, default: "size-4"

  def icon(%{name: "panel-left"} = assigns) do
    ~H"""
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="1.5"
      aria-hidden="true"
      class={@class}
    >
      <rect x="3" y="4.5" width="18" height="15" rx="2" />
      <path d="M9 4.5v15" />
    </svg>
    """
  end

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 300,
      transition:
        {"transition-all ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all ease-in duration-200", "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    # When using gettext, we typically pass the strings we want
    # to translate as a static argument:
    #
    #     # Translate the number of files with plural rules
    #     dngettext("errors", "1 file", "%{count} files", count)
    #
    # However the error messages in our forms and APIs are generated
    # dynamically, so we need to translate them by calling Gettext
    # with our gettext backend as first argument. Translations are
    # available in the errors.po file (as we use the "errors" domain).
    if count = opts[:count] do
      Gettext.dngettext(DelivestWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(DelivestWeb.Gettext, "errors", msg, opts)
    end
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end
end
