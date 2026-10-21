defmodule DelivestWeb.Staff.PromotionLive.PromotionFormComponent do
  use DelivestWeb, :live_component

  alias Delivest.{Net, Promo}
  alias Delivest.Promo.Dsl
  alias DelivestWeb.Staff.OrderLive.OrderHelpers

  alias DelivestWeb.Staff.PromotionLive.{
    PromotionHelpers,
    RulesBuilder,
    RulesHelp,
    RulesText
  }

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)

    if socket.assigns[:form] && socket.assigns[:loaded_id] == assigns.promotion.id do
      {:ok, socket}
    else
      {mode, builder} = initial_builder(assigns.promotion.rules)

      {:ok,
       socket
       |> assign(
         loaded_id: assigns.promotion.id,
         products: product_options(assigns.branch_id),
         mode: mode,
         builder: builder,
         params: %{},
         show_errors: false,
         mode_error: false
       )
       |> refresh(nil)}
    end
  end

  @impl true
  def handle_event("validate", %{"promotion" => params} = all, socket) do
    {:noreply, socket |> take_params(params, all) |> refresh(:validate)}
  end

  def handle_event("save", %{"promotion" => params} = all, socket) do
    socket = take_params(socket, params, all)

    if builder_errors(socket.assigns) == %{} do
      case save(socket.assigns, full_params(socket.assigns)) do
        {:ok, promotion} ->
          send(self(), {__MODULE__, {:saved, promotion}})
          {:noreply, socket}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:noreply, socket |> assign(show_errors: true) |> assign_form(changeset)}

        {:error, :forbidden} ->
          {:noreply,
           put_flash(
             socket,
             :error,
             gettext("You don't have permission to perform this action.")
           )}
      end
    else
      {:noreply, socket |> assign(show_errors: true) |> refresh(:insert)}
    end
  end

  def handle_event("add_condition", %{"type" => type}, socket),
    do: update_builder(socket, &RulesBuilder.add_condition(&1, type))

  def handle_event("remove_condition", %{"index" => index}, socket),
    do: update_builder(socket, &RulesBuilder.remove_condition(&1, String.to_integer(index)))

  def handle_event("add_effect", %{"type" => type}, socket),
    do: update_builder(socket, &RulesBuilder.add_effect(&1, type))

  def handle_event("remove_effect", %{"index" => index}, socket),
    do: update_builder(socket, &RulesBuilder.remove_effect(&1, String.to_integer(index)))

  def handle_event("remove_product", %{"index" => index, "slug" => slug}, socket),
    do: update_builder(socket, &RulesBuilder.remove_product(&1, String.to_integer(index), slug))

  def handle_event("text_mode", _params, socket) do
    params =
      Map.put(socket.assigns.params, "rules", RulesBuilder.to_rules(socket.assigns.builder))

    {:noreply,
     socket
     |> assign(mode: :text, params: params, mode_error: false)
     |> refresh(form_action(socket))}
  end

  def handle_event("builder_mode", _params, socket) do
    rules = Ecto.Changeset.get_field(socket.assigns.form.source, :rules)

    case RulesBuilder.from_rules(rules) do
      {:ok, builder} ->
        {:noreply,
         socket
         |> assign(mode: :builder, builder: builder, mode_error: false)
         |> refresh(form_action(socket))}

      :error ->
        {:noreply, assign(socket, mode_error: true)}
    end
  end

  defp take_params(socket, params, all) do
    socket = assign(socket, params: params)

    if socket.assigns.mode == :builder,
      do: assign(socket, builder: RulesBuilder.from_params(Map.get(all, "builder", %{}))),
      else: socket
  end

  defp update_builder(socket, fun) do
    {:noreply,
     socket |> assign(builder: fun.(socket.assigns.builder)) |> refresh(form_action(socket))}
  end

  defp form_action(socket), do: socket.assigns.form.source.action

  defp refresh(socket, action) do
    changeset =
      socket.assigns.promotion
      |> Promo.change_promotion(full_params(socket.assigns))
      |> Map.put(:action, action)

    assign_form(socket, changeset)
  end

  defp full_params(%{mode: :builder, builder: builder, params: params}),
    do:
      params
      |> Map.put("rules", RulesBuilder.to_rules(builder))
      |> PromotionHelpers.window_to_utc()

  defp full_params(%{params: params}), do: PromotionHelpers.window_to_utc(params)

  defp builder_errors(%{mode: :builder, builder: builder}), do: RulesBuilder.errors(builder)
  defp builder_errors(_assigns), do: %{}

  defp save(%{action: :new} = assigns, params),
    do: Promo.create_promotion(assigns.current_staff, assigns.branch_id, params)

  defp save(assigns, params),
    do: Promo.update_promotion(assigns.current_staff, assigns.promotion, params)

  defp initial_builder(nil), do: {:builder, RulesBuilder.new()}

  defp initial_builder(rules) do
    case RulesBuilder.from_rules(rules) do
      {:ok, builder} -> {:builder, builder}
      :error -> {:text, RulesBuilder.new()}
    end
  end

  defp assign_form(socket, changeset) do
    rules = Ecto.Changeset.get_field(changeset, :rules)

    assign(socket,
      form: to_form(changeset),
      rules: rules,
      preview: preview(rules, socket.assigns.products)
    )
  end

  defp preview(rules, products) do
    case Dsl.parse(rules) do
      {:ok, strategy} ->
        RulesText.describe(strategy, Map.new(products, fn {name, slug} -> {slug, name} end))

      {:error, _errors} ->
        nil
    end
  end

  defp product_options(branch_id),
    do: branch_id |> Net.list_branch_products() |> Enum.map(&{&1.name, &1.slug})

  defp rules_placeholder, do: "when subtotal >= 1500\nthen discount 10%"

  defp rules_errors(form) do
    form[:rules].errors
    |> Enum.map(&translate_error/1)
    |> Enum.map(&String.replace(&1, ~r/^\d+:\d+ /, ""))
  end

  defp condition_label("subtotal"), do: gettext("Cart total")
  defp condition_label("quantity"), do: gettext("Number of items")
  defp condition_label("has"), do: gettext("Product in cart")
  defp condition_label("fulfillment"), do: gettext("Fulfillment method")
  defp condition_label("time"), do: gettext("Time of day")
  defp condition_label("weekday"), do: gettext("Days of week")

  defp condition_icon("subtotal"), do: "hero-banknotes"
  defp condition_icon("quantity"), do: "hero-square-3-stack-3d"
  defp condition_icon("has"), do: "hero-shopping-bag"
  defp condition_icon("fulfillment"), do: "hero-truck"
  defp condition_icon("time"), do: "hero-clock"
  defp condition_icon("weekday"), do: "hero-calendar-days"

  defp effect_label("percent"), do: gettext("Percentage discount")
  defp effect_label("amount"), do: gettext("Fixed discount")
  defp effect_label("gift"), do: gettext("Gift product")
  defp effect_label("price"), do: gettext("Special price")

  defp effect_icon("percent"), do: "hero-receipt-percent"
  defp effect_icon("amount"), do: "hero-banknotes"
  defp effect_icon("gift"), do: "hero-gift"
  defp effect_icon("price"), do: "hero-tag"

  defp op_options do
    [
      {gettext("at least"), ">="},
      {gettext("more than"), ">"},
      {gettext("at most"), "<="},
      {gettext("less than"), "<"},
      {gettext("exactly"), "="}
    ]
  end

  defp weekday_label("mon"), do: gettext("Mon")
  defp weekday_label("tue"), do: gettext("Tue")
  defp weekday_label("wed"), do: gettext("Wed")
  defp weekday_label("thu"), do: gettext("Thu")
  defp weekday_label("fri"), do: gettext("Fri")
  defp weekday_label("sat"), do: gettext("Sat")
  defp weekday_label("sun"), do: gettext("Sun")

  defp product_select_options(products, current) do
    if current in ["", nil] or Enum.any?(products, fn {_name, slug} -> slug == current end),
      do: products,
      else: products ++ [{gettext("%{slug} (not found)", slug: current), current}]
  end

  defp product_name(products, slug) do
    Enum.find_value(products, slug, fn {name, product_slug} -> product_slug == slug && name end)
  end

  defp row_error(assigns, key), do: assigns.show_errors && Map.get(assigns.errors, key)

  @impl true
  def render(assigns) do
    assigns = assign(assigns, errors: builder_errors(assigns))

    ~H"""
    <div class="h-full flex flex-col">
      <.form
        for={@form}
        id="promotion-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
        class="flex flex-col h-full"
      >
        <div class="flex-1 overflow-y-auto space-y-6">
          <.step number={1} title={gettext("Basics")}>
            <.input field={@form[:name]} type="text" label={gettext("Name")} maxlength="100" />
            <.input
              field={@form[:description]}
              type="textarea"
              rows="2"
              label={gettext("Description for customers")}
              maxlength="500"
            />

            <.input
              field={@form[:kind]}
              type="select"
              label={gettext("Type")}
              options={PromotionHelpers.kind_options()}
              disabled={@action != :new}
            />

            <div :if={to_string(@form[:kind].value) == "public_code"}>
              <.input
                field={@form[:code]}
                type="text"
                label={gettext("Promo code")}
                placeholder="SUMMER2026"
                maxlength="32"
                class="input w-full font-mono uppercase"
              />
            </div>

            <p
              :if={to_string(@form[:kind].value) == "personal_code"}
              class="text-xs text-base-content/60"
            >
              {gettext(
                "Unique codes are issued to clients from the promotion list or the client page."
              )}
            </p>
          </.step>

          <%= if @mode == :builder do %>
            <.step
              number={2}
              title={gettext("When does it apply?")}
              hint={gettext("Leave empty to apply to every order.")}
            >
              <div :if={length(@builder.conditions) > 1} class="flex items-center gap-2 text-sm">
                <span>{gettext("Apply when")}</span>
                <select name="builder[match]" class="select select-sm w-auto" id="builder-match">
                  {Phoenix.HTML.Form.options_for_select(
                    [
                      {gettext("all conditions are met"), "all"},
                      {gettext("any condition is met"), "any"}
                    ],
                    @builder.match
                  )}
                </select>
              </div>
              <input
                :if={length(@builder.conditions) <= 1}
                type="hidden"
                name="builder[match]"
                value={@builder.match}
              />

              <div id="builder-conditions" class="space-y-2">
                <.rule_card
                  :for={{row, index} <- Enum.with_index(@builder.conditions)}
                  id={"condition-#{index}"}
                  icon={condition_icon(row["type"])}
                  title={condition_label(row["type"])}
                  error={row_error(assigns, {:condition, index})}
                  remove="remove_condition"
                  index={index}
                  target={@myself}
                >
                  <:connector :if={index > 0}>
                    {if @builder.match == "any", do: gettext("or"), else: gettext("and")}
                  </:connector>
                  <input
                    type="hidden"
                    name={"builder[conditions][#{index}][type]"}
                    value={row["type"]}
                  />
                  <.condition_fields row={row} index={index} products={@products} />
                </.rule_card>
              </div>

              <.add_buttons
                types={RulesBuilder.condition_types()}
                label={&condition_label/1}
                icon={&condition_icon/1}
                event="add_condition"
                target={@myself}
                id="add-condition"
              />
            </.step>

            <.step number={3} title={gettext("What does the customer get?")}>
              <div id="builder-effects" class="space-y-2">
                <.rule_card
                  :for={{row, index} <- Enum.with_index(@builder.effects)}
                  id={"effect-#{index}"}
                  icon={effect_icon(row["type"])}
                  title={effect_label(row["type"])}
                  error={row_error(assigns, {:effect, index})}
                  remove="remove_effect"
                  index={index}
                  target={@myself}
                >
                  <input type="hidden" name={"builder[effects][#{index}][type]"} value={row["type"]} />
                  <.effect_fields row={row} index={index} products={@products} target={@myself} />
                </.rule_card>
              </div>

              <p
                :if={@builder.effects == []}
                class="rounded-box border border-dashed border-base-300 p-3 text-sm text-base-content/60"
              >
                {gettext("Add at least one reward.")}
              </p>

              <.add_buttons
                types={RulesBuilder.effect_types()}
                label={&effect_label/1}
                icon={&effect_icon/1}
                event="add_effect"
                target={@myself}
                id="add-effect"
              />
            </.step>

            <div
              :if={@show_errors and (@errors != %{} or rules_errors(@form) != [])}
              id="builder-errors"
              class="rounded-box border border-error/40 bg-error/5 p-3 text-sm text-error space-y-1"
            >
              <p :if={@errors != %{}}>{gettext("Fill in the highlighted fields.")}</p>
              <p :for={message <- rules_errors(@form)}>{message}</p>
            </div>

            <.rules_preview preview={@preview} rules={@rules} />

            <button
              type="button"
              class="btn btn-ghost btn-xs text-base-content/60"
              phx-click="text_mode"
              phx-target={@myself}
            >
              <.icon name="hero-code-bracket" class="size-4" /> {gettext("Edit as text")}
            </button>
          <% else %>
            <.step number={2} title={gettext("Rules")}>
              <.input
                field={@form[:rules]}
                type="textarea"
                rows="6"
                class="textarea w-full font-mono text-sm"
                spellcheck="false"
                placeholder={rules_placeholder()}
              />

              <.rules_preview preview={@preview} />

              <RulesHelp.render_help />

              <div class="flex flex-wrap items-center gap-2">
                <button
                  type="button"
                  class="btn btn-sm btn-outline"
                  phx-click="builder_mode"
                  phx-target={@myself}
                >
                  <.icon name="hero-adjustments-horizontal" class="size-4" />
                  {gettext("Back to the constructor")}
                </button>
                <span :if={@mode_error} class="text-xs text-warning">
                  {gettext("These rules are too complex for the constructor.")}
                </span>
              </div>
            </.step>
          <% end %>

          <.step
            number={4}
            title={gettext("Limits")}
            hint={gettext("Leave empty for no limit. Per-client limits need the client's phone.")}
          >
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-x-3">
              <.input
                field={@form[:starts_at]}
                type="datetime-local"
                label={gettext("Starts")}
                value={PromotionHelpers.local_input(@form[:starts_at].value)}
              />
              <.input
                field={@form[:ends_at]}
                type="datetime-local"
                label={gettext("Ends")}
                value={PromotionHelpers.local_input(@form[:ends_at].value)}
              />
              <.input
                field={@form[:usage_limit]}
                type="number"
                min="1"
                label={gettext("Total uses")}
              />
              <.input
                field={@form[:per_client_limit]}
                type="number"
                min="1"
                label={gettext("Uses per client")}
              />
            </div>
          </.step>

          <.step
            number={5}
            title={gettext("Compatibility")}
            hint={
              gettext(
                "An entered promo code always goes first. Automatic promotions follow by priority; a non-combinable one blocks the rest."
              )
            }
          >
            <.input field={@form[:priority]} type="number" label={gettext("Priority")} />
            <.input
              field={@form[:combinable]}
              type="checkbox"
              label={gettext("Combines with other combinable promotions")}
            />
            <.input field={@form[:enabled]} type="checkbox" label={gettext("Enabled")} />
          </.step>
        </div>

        <div class="shrink-0 pt-4 mt-4 border-t border-base-200 flex justify-end gap-3">
          <.link patch={@patch} class="btn btn-ghost">{gettext("Cancel")}</.link>
          <button type="submit" class="btn btn-primary" phx-disable-with={gettext("Saving...")}>
            {gettext("Save")}
          </button>
        </div>
      </.form>
    </div>
    """
  end

  attr :number, :integer, required: true
  attr :title, :string, required: true
  attr :hint, :string, default: nil
  slot :inner_block, required: true

  defp step(assigns) do
    ~H"""
    <section class="space-y-3">
      <div class="flex items-center gap-2">
        <span class="size-6 rounded-full bg-primary text-primary-content text-xs font-bold flex items-center justify-center shrink-0">
          {@number}
        </span>
        <h3 class="font-bold">{@title}</h3>
      </div>
      <p :if={@hint} class="text-xs text-base-content/60">{@hint}</p>
      {render_slot(@inner_block)}
    </section>
    """
  end

  attr :id, :string, required: true
  attr :icon, :string, required: true
  attr :title, :string, required: true
  attr :error, :any, default: nil
  attr :remove, :string, required: true
  attr :index, :integer, required: true
  attr :target, :any, required: true
  slot :connector
  slot :inner_block, required: true

  defp rule_card(assigns) do
    ~H"""
    <div id={@id}>
      <div
        :if={@connector != []}
        class="text-center text-xs font-bold uppercase text-base-content/50 -mt-1 mb-1"
      >
        {render_slot(@connector)}
      </div>
      <div class={[
        "rounded-box border p-3 space-y-2 bg-base-100",
        if(@error, do: "border-error", else: "border-base-300")
      ]}>
        <div class="flex items-center gap-2">
          <.icon name={@icon} class="size-4 text-primary" />
          <span class="text-sm font-bold flex-1">{@title}</span>
          <button
            type="button"
            class="btn btn-ghost btn-xs btn-square text-base-content/50 hover:text-error"
            phx-click={@remove}
            phx-value-index={@index}
            phx-target={@target}
            title={gettext("Remove")}
          >
            <.icon name="hero-x-mark" class="size-4" />
          </button>
        </div>
        {render_slot(@inner_block)}
        <p :if={@error} class="text-xs text-error">{@error}</p>
      </div>
    </div>
    """
  end

  attr :types, :list, required: true
  attr :label, :any, required: true
  attr :icon, :any, required: true
  attr :event, :string, required: true
  attr :target, :any, required: true
  attr :id, :string, required: true

  defp add_buttons(assigns) do
    ~H"""
    <div id={@id} class="flex flex-wrap gap-1.5">
      <button
        :for={type <- @types}
        type="button"
        class="btn btn-xs btn-outline btn-primary"
        phx-click={@event}
        phx-value-type={type}
        phx-target={@target}
      >
        <.icon name="hero-plus" class="size-3" />
        <.icon name={@icon.(type)} class="size-3.5" />
        {@label.(type)}
      </button>
    </div>
    """
  end

  attr :preview, :map, default: nil
  attr :rules, :string, default: nil

  defp rules_preview(assigns) do
    ~H"""
    <div
      :if={@preview}
      id="rules-preview"
      class="rounded-box border border-success/30 bg-success/5 p-3 text-sm space-y-1"
    >
      <p :if={@preview.condition}>
        <span class="font-bold">{gettext("When")}:</span> {@preview.condition}
      </p>
      <p :if={!@preview.condition} class="text-base-content/60">{gettext("Always")}</p>
      <p>
        <span class="font-bold">{gettext("Then")}:</span> {Enum.join(@preview.effects, "; ")}
      </p>
      <details :if={@rules} class="pt-1">
        <summary class="cursor-pointer select-none text-xs text-base-content/50">
          {gettext("Rules code")}
        </summary>
        <pre
          id="rules-code"
          class="mt-1 rounded bg-base-100 border border-base-300 p-2 text-xs overflow-x-auto"
        >{@rules}</pre>
      </details>
    </div>
    """
  end

  attr :row, :map, required: true
  attr :index, :integer, required: true
  attr :products, :list, required: true

  defp condition_fields(%{row: %{"type" => type}} = assigns) when type in ~w(subtotal quantity) do
    ~H"""
    <div class="flex gap-2">
      <select
        name={"builder[conditions][#{@index}][op]"}
        class="select select-sm w-36 shrink-0"
        id={"builder-c#{@index}-op"}
      >
        {Phoenix.HTML.Form.options_for_select(op_options(), @row["op"])}
      </select>
      <label class="input input-sm flex-1">
        <input
          type="number"
          min="0"
          name={"builder[conditions][#{@index}][value]"}
          value={@row["value"]}
          id={"builder-c#{@index}-value"}
          placeholder={if @row["type"] == "subtotal", do: "1500", else: "3"}
        />
        <span class="text-base-content/50">
          {if @row["type"] == "subtotal", do: "₽", else: gettext("pcs")}
        </span>
      </label>
    </div>
    """
  end

  defp condition_fields(%{row: %{"type" => "has"}} = assigns) do
    ~H"""
    <.product_and_count
      prefix={"builder[conditions][#{@index}]"}
      id={"builder-c#{@index}"}
      row={@row}
      products={@products}
    />
    """
  end

  defp condition_fields(%{row: %{"type" => "fulfillment"}} = assigns) do
    ~H"""
    <.pills
      name={"builder[conditions][#{@index}][values][]"}
      id={"builder-c#{@index}"}
      selected={@row["values"]}
      options={Enum.map(RulesBuilder.fulfillments(), &{OrderHelpers.fulfillment_label(&1), &1})}
    />
    """
  end

  defp condition_fields(%{row: %{"type" => "weekday"}} = assigns) do
    ~H"""
    <.pills
      name={"builder[conditions][#{@index}][values][]"}
      id={"builder-c#{@index}"}
      selected={@row["values"]}
      options={Enum.map(RulesBuilder.weekdays(), &{weekday_label(&1), &1})}
    />
    """
  end

  defp condition_fields(%{row: %{"type" => "time"}} = assigns) do
    ~H"""
    <div class="flex items-center gap-2">
      <span class="text-sm text-base-content/60">{gettext("from")}</span>
      <input
        type="time"
        class="input input-sm flex-1"
        name={"builder[conditions][#{@index}][from]"}
        value={@row["from"]}
        id={"builder-c#{@index}-from"}
      />
      <span class="text-sm text-base-content/60">{gettext("to")}</span>
      <input
        type="time"
        class="input input-sm flex-1"
        name={"builder[conditions][#{@index}][to]"}
        value={@row["to"]}
        id={"builder-c#{@index}-to"}
      />
    </div>
    """
  end

  attr :row, :map, required: true
  attr :index, :integer, required: true
  attr :products, :list, required: true
  attr :target, :any, required: true

  defp effect_fields(%{row: %{"type" => type}} = assigns) when type in ~w(percent amount) do
    ~H"""
    <label class="input input-sm w-full">
      <input
        type="number"
        min="1"
        max={if @row["type"] == "percent", do: "100"}
        name={"builder[effects][#{@index}][value]"}
        value={@row["value"]}
        id={"builder-e#{@index}-value"}
        placeholder={if @row["type"] == "percent", do: "10", else: "300"}
      />
      <span class="text-base-content/50">{if @row["type"] == "percent", do: "%", else: "₽"}</span>
    </label>

    <div class="join w-full">
      <label
        :for={
          {label, value} <- [
            {gettext("Whole cart"), "cart"},
            {gettext("Selected products"), "products"}
          ]
        }
        class={[
          "join-item btn btn-xs flex-1",
          @row["target"] == value && "btn-primary"
        ]}
      >
        <input
          type="radio"
          class="hidden"
          name={"builder[effects][#{@index}][target]"}
          value={value}
          checked={@row["target"] == value}
        />
        {label}
      </label>
    </div>

    <label :if={@row["type"] == "percent" and @row["target"] == "cart"} class="input input-sm w-full">
      <span class="text-base-content/60 text-xs">{gettext("Max discount")}</span>
      <input
        type="number"
        min="1"
        name={"builder[effects][#{@index}][cap]"}
        value={@row["cap"]}
        id={"builder-e#{@index}-cap"}
        placeholder={gettext("no limit")}
      />
      <span class="text-base-content/50">₽</span>
    </label>
    <input
      :if={@row["type"] == "percent" and @row["target"] != "cart"}
      type="hidden"
      name={"builder[effects][#{@index}][cap]"}
      value=""
    />

    <div :if={@row["target"] == "products"} class="space-y-2">
      <div class="flex flex-wrap gap-1">
        <span :for={slug <- @row["products"]} class="badge badge-primary badge-outline gap-1 pr-1">
          <input type="hidden" name={"builder[effects][#{@index}][products][]"} value={slug} />
          {product_name(@products, slug)}
          <button
            type="button"
            class="hover:text-error"
            phx-click="remove_product"
            phx-value-index={@index}
            phx-value-slug={slug}
            phx-target={@target}
          >
            <.icon name="hero-x-mark" class="size-3" />
          </button>
        </span>
      </div>
      <input type="hidden" name={"builder[effects][#{@index}][products][]"} value="" />
      <select
        name={"builder[effects][#{@index}][add]"}
        class="select select-sm w-full"
        id={"builder-e#{@index}-add-#{length(@row["products"])}"}
      >
        <option value="">{gettext("+ Add product")}</option>
        {Phoenix.HTML.Form.options_for_select(
          Enum.reject(@products, fn {_name, slug} -> slug in @row["products"] end),
          nil
        )}
      </select>
    </div>
    """
  end

  defp effect_fields(%{row: %{"type" => "gift"}} = assigns) do
    ~H"""
    <.product_and_count
      prefix={"builder[effects][#{@index}]"}
      id={"builder-e#{@index}"}
      row={@row}
      products={@products}
    />
    """
  end

  defp effect_fields(%{row: %{"type" => "price"}} = assigns) do
    ~H"""
    <div class="flex gap-2">
      <select
        name={"builder[effects][#{@index}][product]"}
        class="select select-sm flex-1 min-w-0"
        id={"builder-e#{@index}-product"}
      >
        <option value="">{gettext("Choose a product")}</option>
        {Phoenix.HTML.Form.options_for_select(
          product_select_options(@products, @row["product"]),
          @row["product"]
        )}
      </select>
      <label class="input input-sm w-28 shrink-0">
        <input
          type="number"
          min="0"
          name={"builder[effects][#{@index}][price]"}
          value={@row["price"]}
          id={"builder-e#{@index}-price"}
          placeholder="399"
        />
        <span class="text-base-content/50">₽</span>
      </label>
    </div>
    """
  end

  attr :prefix, :string, required: true
  attr :id, :string, required: true
  attr :row, :map, required: true
  attr :products, :list, required: true

  defp product_and_count(assigns) do
    ~H"""
    <div class="flex gap-2">
      <select
        name={"#{@prefix}[product]"}
        class="select select-sm flex-1 min-w-0"
        id={"#{@id}-product"}
      >
        <option value="">{gettext("Choose a product")}</option>
        {Phoenix.HTML.Form.options_for_select(
          product_select_options(@products, @row["product"]),
          @row["product"]
        )}
      </select>
      <label class="input input-sm w-24 shrink-0">
        <span class="text-base-content/50">×</span>
        <input
          type="number"
          min="1"
          max="99"
          name={"#{@prefix}[count]"}
          value={@row["count"]}
          id={"#{@id}-count"}
        />
      </label>
    </div>
    """
  end

  attr :name, :string, required: true
  attr :id, :string, required: true
  attr :selected, :list, required: true
  attr :options, :list, required: true

  defp pills(assigns) do
    ~H"""
    <div class="flex flex-wrap gap-1.5">
      <input type="hidden" name={@name} value="" />
      <label
        :for={{label, value} <- @options}
        class={[
          "btn btn-xs",
          if(value in @selected, do: "btn-primary", else: "btn-outline border-base-300")
        ]}
      >
        <input
          type="checkbox"
          class="hidden"
          name={@name}
          value={value}
          id={"#{@id}-#{value}"}
          checked={value in @selected}
        />
        {label}
      </label>
    </div>
    """
  end
end
