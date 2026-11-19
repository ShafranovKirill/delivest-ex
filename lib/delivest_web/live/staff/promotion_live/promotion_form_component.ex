defmodule DelivestWeb.Staff.PromotionLive.PromotionFormComponent do
  use DelivestWeb, :live_component

  alias Delivest.{Net, Promo, Repo}
  alias Delivest.Integrations.Crm.Certificates
  alias Delivest.Promo.CertificateComparison
  alias Delivest.Promo.Dsl
  alias DelivestWeb.Staff.OrderLive.OrderHelpers
  alias Phoenix.LiveView.JS

  alias DelivestWeb.Staff.PromotionLive.{
    PromotionHelpers,
    RulesBuilder,
    RulesHelp,
    RulesText
  }

  def update(%{picker_result: %{ids: ids}}, socket) do
    %{kind: kind, index: index} = socket.assigns.picker_target
    allowed = Map.new(socket.assigns.picker_products, &{&1.id, &1.slug})
    slugs = ids |> Enum.map(&Map.get(allowed, &1)) |> Enum.reject(&is_nil/1)

    rows =
      if kind == :condition,
        do: socket.assigns.builder.conditions,
        else: socket.assigns.builder.effects

    rows =
      List.update_at(rows, index, fn row ->
        if Map.has_key?(row, "product"),
          do: Map.put(row, "product", List.first(slugs) || ""),
          else: Map.put(row, "products", slugs)
      end)

    builder =
      if kind == :condition,
        do: %{socket.assigns.builder | conditions: rows},
        else: %{socket.assigns.builder | effects: rows}

    {:ok, socket |> assign(builder: builder, picker_target: nil) |> refresh(form_action(socket))}
  end

  def update(%{picker_cancelled: true}, socket), do: {:ok, assign(socket, picker_target: nil)}

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)

    if socket.assigns[:form] && socket.assigns[:loaded_id] == assigns.promotion.id do
      {:ok, socket}
    else
      {mode, builder} =
        if assigns.template in ~w(gift_threshold bundle pickup),
          do: {:builder, RulesBuilder.template(assigns.template)},
          else: initial_builder(assigns.promotion.rules)

      {:ok,
       socket
       |> assign(
         loaded_id: assigns.promotion.id,
         products: product_options(assigns.branch_id),
         picker_products:
           assigns.branch_id |> Net.list_branch_products() |> Repo.preload(:category),
         picker_target: nil,
         mode: mode,
         builder: builder,
         params: %{},
         show_errors: false,
         mode_error: false,
         certificate_provider: (assigns.promotion.crm_certificate || %{})["provider"] || "",
         certificate_code: (assigns.promotion.crm_certificate || %{})["code"] || "",
         certificate_original: assigns.promotion.crm_certificate,
         certificate_result: assigns.promotion.crm_certificate,
         certificate_token: nil,
         certificate_error: nil
       )
       |> refresh(nil)}
    end
  end

  @impl true
  def handle_event("validate", %{"promotion" => params} = all, socket) do
    {:noreply, socket |> take_params(params, all) |> refresh(:validate)}
  end

  def handle_event("save", %{"promotion" => params} = all, socket) do
    socket = socket |> take_params(params, all) |> assign(show_errors: true) |> refresh(:insert)

    if certificate_save_token(socket.assigns) == :unverified do
      {:noreply, assign(socket, certificate_error: "Сначала проверьте номер сертификата")}
    else
      if builder_errors(socket.assigns) == %{} do
        case save(
               socket.assigns,
               full_params(socket.assigns)
               |> Map.put("crm_certificate_token", certificate_save_token(socket.assigns))
             ) do
          {:ok, promotion} ->
            send(self(), {__MODULE__, {:saved, promotion}})
            {:noreply, push_event(socket, "staff:form-saved", %{id: "promotion-form"})}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:noreply, socket |> assign(show_errors: true) |> assign_form(changeset)}

          {:error, :forbidden} ->
            {:noreply,
             put_flash(
               socket,
               :error,
               gettext("You don't have permission to perform this action.")
             )}

          {:error, _reason} ->
            {:noreply, put_flash(socket, :error, gettext("Failed to save promotion"))}
        end
      else
        {:noreply, socket |> assign(show_errors: true) |> refresh(:insert)}
      end
    end
  end

  def handle_event("check_certificate", _params, socket) do
    case Certificates.verify(
           socket.assigns.current_staff,
           socket.assigns.branch_id,
           socket.assigns.certificate_provider,
           socket.assigns.certificate_code,
           if(socket.assigns.action == :new, do: "promotions.create", else: "promotions.update")
         ) do
      {:ok, snapshot, token} ->
        {:noreply,
         assign(socket,
           certificate_result: snapshot,
           certificate_token: token,
           certificate_error: nil
         )}

      {:error, reason} ->
        {:noreply,
         assign(socket,
           certificate_result: nil,
           certificate_token: nil,
           certificate_error: certificate_error(reason)
         )}
    end
  end

  def handle_event("add_condition", %{"type" => type}, socket),
    do: update_builder(socket, &RulesBuilder.add_condition(&1, type))

  def handle_event("template", %{"type" => type}, socket) when type in ~w(discount first_order),
    do: update_builder(socket, fn _builder -> RulesBuilder.template(type) end)

  def handle_event("remove_condition", %{"index" => index}, socket),
    do: update_builder(socket, &RulesBuilder.remove_condition(&1, String.to_integer(index)))

  def handle_event("add_effect", %{"type" => type}, socket),
    do: update_builder(socket, &RulesBuilder.add_effect(&1, type))

  def handle_event("remove_effect", %{"index" => index}, socket),
    do: update_builder(socket, &RulesBuilder.remove_effect(&1, String.to_integer(index)))

  def handle_event("remove_product", %{"index" => index, "slug" => slug} = params, socket),
    do:
      update_builder(
        socket,
        &RulesBuilder.remove_product(&1, String.to_integer(index), slug, params["kind"])
      )

  def handle_event("open_product_picker", %{"kind" => kind, "index" => index}, socket)
      when kind in ~w(condition effect) do
    index = String.to_integer(index)

    rows =
      if kind == "condition",
        do: socket.assigns.builder.conditions,
        else: socket.assigns.builder.effects

    case Enum.at(rows, index) do
      %{} = row ->
        target = %{
          kind: String.to_existing_atom(kind),
          index: index,
          slugs: List.wrap(row["products"] || row["product"])
        }

        {:noreply, assign(socket, picker_target: target)}

      _ ->
        {:noreply, socket}
    end
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

  def handle_event("text_mode", _params, socket), do: {:noreply, socket}

  defp take_params(socket, params, all) do
    params = Map.merge(Map.take(socket.assigns.params, ["code"]), params)
    socket = assign(socket, params: params)
    certificate = Map.get(all, "certificate", %{})
    certificate = if is_map(certificate), do: certificate, else: %{}
    provider = Map.get(certificate, "provider", socket.assigns.certificate_provider)
    code = Map.get(certificate, "code", socket.assigns.certificate_code)
    provider = if is_binary(provider), do: provider, else: ""
    code = if is_binary(code), do: code, else: ""

    socket =
      cond do
        socket.assigns.action == :new and params["kind"] in ["personal_code", "automatic"] ->
          assign(socket,
            certificate_provider: "",
            certificate_code: "",
            certificate_result: nil,
            certificate_token: nil,
            certificate_error: nil
          )

        {provider, code} ==
            {socket.assigns.certificate_provider, socket.assigns.certificate_code} ->
          socket

        true ->
          assign(socket,
            certificate_provider: provider,
            certificate_code: code,
            certificate_result: nil,
            certificate_token: nil,
            certificate_error: nil
          )
      end

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

    changeset =
      if action == :validate and not socket.assigns.show_errors do
        %{
          changeset
          | errors:
              Enum.filter(changeset.errors, fn {key, _} ->
                Map.has_key?(socket.assigns.params, to_string(key)) and
                  not Map.has_key?(socket.assigns.params, "_unused_#{key}")
              end)
        }
      else
        changeset
      end

    assign_form(socket, changeset)
  end

  defp full_params(%{mode: :builder, builder: builder} = assigns),
    do:
      assigns.params
      |> Map.put("rules", RulesBuilder.to_rules(builder))
      |> put_kind(assigns)
      |> PromotionHelpers.window_to_utc()

  defp full_params(assigns),
    do: assigns.params |> put_kind(assigns) |> PromotionHelpers.window_to_utc()

  defp put_kind(params, %{action: :edit, promotion: promotion}),
    do: Map.put(params, "kind", to_string(promotion.kind))

  defp put_kind(params, %{promotion: promotion}),
    do:
      Map.put(
        params,
        "kind",
        if(params["kind"] in ~w(public_code personal_code automatic),
          do: params["kind"],
          else: to_string(promotion.kind)
        )
      )

  defp builder_errors(%{mode: :builder, builder: builder, template: "bundle"}) do
    errors = RulesBuilder.errors(builder)

    {_, duplicate} =
      builder.conditions
      |> Enum.with_index()
      |> Enum.reduce({MapSet.new(), nil}, fn
        {%{"type" => "has", "product" => product}, index}, {seen, duplicate}
        when is_binary(product) and product != "" ->
          if MapSet.member?(seen, product),
            do: {seen, duplicate || index},
            else: {MapSet.put(seen, product), duplicate}

        _, state ->
          state
      end)

    if duplicate,
      do: Map.put(errors, {:condition, duplicate}, "Выберите другой товар для набора"),
      else: errors
  end

  defp builder_errors(%{mode: :builder, builder: builder}), do: RulesBuilder.errors(builder)
  defp builder_errors(_assigns), do: %{}

  defp save(%{action: :new} = assigns, params),
    do:
      Promo.create_promotion(
        Delivest.Identity.fresh_staff(assigns.current_staff),
        assigns.branch_id,
        params
      )

  defp save(assigns, params),
    do:
      Promo.update_promotion(
        Delivest.Identity.fresh_staff(assigns.current_staff),
        assigns.promotion,
        params
      )

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

  defp picker_single?(builder, %{kind: kind, index: index}) do
    rows = if kind == :condition, do: builder.conditions, else: builder.effects
    rows |> Enum.at(index, %{}) |> Map.has_key?("product")
  end

  defp rules_placeholder, do: "when subtotal >= 1500\nthen discount 10%"

  defp template_hint("gift_threshold"),
    do: "Укажите минимальную сумму, подарок и количество."

  defp template_hint("bundle"),
    do: "Выберите два разных товара и укажите скидку на заказ."

  defp template_hint("pickup"),
    do: "Укажите награду для самовывоза."

  defp condition_label("subtotal"), do: gettext("Cart total")
  defp condition_label("quantity"), do: gettext("Number of items")
  defp condition_label("has_any"), do: gettext("N products from a list")
  defp condition_label("has"), do: gettext("Product in cart")
  defp condition_label("fulfillment"), do: gettext("Fulfillment method")
  defp condition_label("time"), do: gettext("Time of day")
  defp condition_label("weekday"), do: gettext("Days of week")
  defp condition_label("first_order"), do: gettext("First website order")

  defp condition_icon("subtotal"), do: "hero-banknotes"
  defp condition_icon("quantity"), do: "hero-square-3-stack-3d"
  defp condition_icon("has_any"), do: "hero-shopping-bag"
  defp condition_icon("has"), do: "hero-shopping-bag"
  defp condition_icon("fulfillment"), do: "hero-truck"
  defp condition_icon("time"), do: "hero-clock"
  defp condition_icon("weekday"), do: "hero-calendar-days"
  defp condition_icon("first_order"), do: "hero-sparkles"

  defp effect_label("percent"), do: gettext("Percentage discount")
  defp effect_label("amount"), do: gettext("Fixed discount")
  defp effect_label("gift_any"), do: gettext("Gift choice")
  defp effect_label("gift"), do: gettext("Gift product")
  defp effect_label("price"), do: gettext("Special price")

  defp effect_icon("percent"), do: "hero-receipt-percent"
  defp effect_icon("amount"), do: "hero-banknotes"
  defp effect_icon("gift_any"), do: "hero-gift"
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

  defp product_name(products, slug) do
    Enum.find_value(products, slug, fn {name, product_slug} -> product_slug == slug && name end)
  end

  defp row_error(assigns, key), do: assigns.show_errors && Map.get(assigns.errors, key)

  @impl true
  def render(assigns) do
    assigns = assign(assigns, errors: builder_errors(assigns))

    ~H"""
    <div>
      <.form
        for={@form}
        id="promotion-form"
        phx-target={@myself}
        phx-change="validate"
        data-staff-dirty
        phx-submit="save"
        class="grid gap-6 lg:grid-cols-[minmax(0,1fr)_22rem] items-start"
      >
        <div class="space-y-4 min-w-0">
          <.step number={1} title={gettext("Basics")}>
            <p class="text-sm text-base-content/70">{gettext("How should it apply?")}</p>
            <div
              id="promotion-kind"
              class="grid gap-2 sm:grid-cols-3"
            >
              <label
                :for={kind <- PromotionHelpers.kinds()}
                class={[
                  "rounded-box border p-3 flex flex-col gap-1 transition-colors",
                  to_string(@form[:kind].value) == to_string(kind) &&
                    "border-primary bg-primary/5 ring-1 ring-primary",
                  to_string(@form[:kind].value) != to_string(kind) && "border-base-300",
                  @action == :new && "cursor-pointer hover:border-primary/60",
                  @action != :new && to_string(@form[:kind].value) != to_string(kind) &&
                    "opacity-40"
                ]}
              >
                <input
                  type="radio"
                  class="hidden"
                  name={@form[:kind].name}
                  value={kind}
                  checked={to_string(@form[:kind].value) == to_string(kind)}
                  disabled={@action != :new}
                />
                <span class="flex items-center gap-2 font-bold text-sm">
                  <.icon name={PromotionHelpers.kind_icon(kind)} class="size-4 text-primary" />
                  {PromotionHelpers.kind_label(kind)}
                </span>
                <span class="text-xs text-base-content/60">
                  {PromotionHelpers.kind_hint(kind)}
                </span>
              </label>
            </div>

            <div class="grid gap-x-4 sm:grid-cols-2">
              <.input field={@form[:name]} type="text" label={gettext("Name")} maxlength="100" />
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
            </div>

            <.input
              field={@form[:description]}
              type="textarea"
              rows="2"
              label={gettext("Description for customers")}
              maxlength="500"
            />

            <p
              :if={to_string(@form[:kind].value) == "personal_code"}
              class="text-xs text-base-content/60"
            >
              {gettext(
                "Unique codes are issued to clients from the promotion list or the client page."
              )}
            </p>
          </.step>

          <div
            :if={to_string(@form[:kind].value) == "public_code"}
            id="promotion-crm-certificate"
            class="rounded-box border border-base-300 p-4 space-y-3"
          >
            <div>
              <p class="font-semibold text-sm">Сертификат CRM</p>
              <p class="text-xs text-base-content/60">
                Можно связать промокод с уже созданным сертификатом. Проверка выполняется только по кнопке.
              </p>
            </div>
            <div class="grid gap-3 sm:grid-cols-2">
              <div>
                <label for="promotion-certificate-provider" class="label">CRM</label>
                <select
                  id="promotion-certificate-provider"
                  name="certificate[provider]"
                  class="select w-full"
                >
                  <option value="" selected={@certificate_provider == ""}>Без сертификата</option>
                  <option value="frontpad" selected={@certificate_provider == "frontpad"}>
                    Frontpad
                  </option>
                  <option value="rkeeper" disabled>r_keeper — проверка пока недоступна</option>
                </select>
              </div>
              <div>
                <label for="promotion-certificate-code" class="label">Номер сертификата</label>
                <input
                  id="promotion-certificate-code"
                  name="certificate[code]"
                  value={@certificate_code}
                  maxlength="20"
                  autocomplete="off"
                  class="input w-full"
                  disabled={@certificate_provider == ""}
                />
              </div>
            </div>
            <button
              type="button"
              class="btn btn-sm btn-outline"
              phx-click="check_certificate"
              phx-target={@myself}
              disabled={@certificate_provider == ""}
            >
              Проверить
            </button>
            <p :if={@certificate_error} class="text-sm text-error">{@certificate_error}</p>
            <div
              :if={@certificate_result && @certificate_provider != ""}
              id="promotion-certificate-result"
              class="space-y-1 text-sm"
            >
              <p class="text-success font-medium">
                Сертификат проверен: {certificate_label(@certificate_result)}
              </p>
              <p
                :for={
                  warning <- CertificateComparison.warnings(@certificate_result, @rules, @branch_id)
                }
                class="text-warning"
              >
                {warning}
              </p>
            </div>
          </div>

          <%= if @mode == :builder do %>
            <p :if={@template} id="promotion-template-hint" class="text-sm text-base-content/70">
              {template_hint(@template)}
            </p>
            <.step
              number={2}
              title={gettext("When does it apply?")}
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

              <p :if={@builder.conditions == []} class="text-sm text-base-content/60">
                Без условий награда действует для всех заказов. Добавьте условие, если нужно ограничение.
              </p>
              <div id="builder-conditions" class="grid gap-2 xl:grid-cols-2">
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
                  <.condition_fields row={row} index={index} products={@products} target={@myself} />
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

            <.step
              number={3}
              title={gettext("What does the customer get?")}
            >
              <div id="builder-effects" class="grid gap-2 xl:grid-cols-2">
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
                id="promotion-reward-error"
                class={[
                  "rounded-box border border-dashed p-3 text-sm",
                  @show_errors && "border-error text-error",
                  !@show_errors && "border-base-300 text-base-content/60"
                ]}
              >
                {if @show_errors,
                  do: "Добавьте награду перед сохранением.",
                  else: "Выберите, что получит клиент."}
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
          <% else %>
            <.step number={2} title={gettext("Rules")}>
              <.input
                field={@form[:rules]}
                type="textarea"
                rows="10"
                class="textarea w-full font-mono text-sm"
                spellcheck="false"
                placeholder={rules_placeholder()}
              />

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
        </div>

        <aside class="space-y-4 lg:sticky lg:top-4">
          <.step title={gettext("Summary")}>
            <.rules_preview preview={@preview} />
            <p :if={!@preview} class="text-sm text-base-content/60">
              {gettext("Add a reward to see what the customer gets.")}
            </p>
          </.step>

          <.step
            title={gettext("Limits")}
            hint={gettext("Leave empty for no limit. Per-client limits need the client's phone.")}
          >
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
            <div class="grid grid-cols-2 gap-x-3">
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

          <div class="flex gap-3">
            <.link patch={@patch} class="btn btn-ghost flex-1">{gettext("Cancel")}</.link>
          </div>
        </aside>
      </.form>
      <.live_component
        :if={@picker_target}
        module={DelivestWeb.Staff.ProductLive.ProductPicker}
        id="promotion-product-picker"
        products={@picker_products}
        selected_ids={
          for product <- @picker_products, product.slug in @picker_target.slugs, do: product.id
        }
        title={gettext("Which products?")}
        mode={if picker_single?(@builder, @picker_target), do: :single, else: :multiple}
        on_save={fn ids -> send_update(__MODULE__, id: @id, picker_result: %{ids: ids}) end}
        on_cancel={fn -> send_update(__MODULE__, id: @id, picker_cancelled: true) end}
      />
    </div>
    """
  end

  attr :number, :integer, default: nil
  attr :title, :string, required: true
  attr :hint, :string, default: nil
  slot :inner_block, required: true

  defp step(assigns) do
    ~H"""
    <section class="rounded-box border border-base-300 bg-base-100 p-4 sm:p-5 space-y-3">
      <div class="flex items-center gap-2">
        <span
          :if={@number}
          class="size-6 rounded-full bg-primary text-primary-content text-xs font-bold flex items-center justify-center shrink-0"
        >
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
    <details id={@id} class="group">
      <summary class="btn btn-sm btn-outline btn-primary cursor-pointer list-none">
        <.icon name="hero-plus" class="size-4" />
        {if @event == "add_effect", do: "Добавить награду", else: "Добавить условие"}
      </summary>
      <div class="flex flex-wrap gap-1.5 pt-3">
        <button
          :for={type <- @types}
          type="button"
          class="btn btn-xs btn-outline btn-primary"
          phx-click={@event}
          phx-value-type={type}
          phx-target={@target}
        >
          <.icon name={@icon.(type)} class="size-3.5" />
          {@label.(type)}
        </button>
      </div>
    </details>
    """
  end

  attr :preview, :map, default: nil

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
    </div>
    """
  end

  attr :row, :map, required: true
  attr :index, :integer, required: true
  attr :products, :list, required: true

  attr :target, :any, required: true

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
          type={if @row["type"] == "subtotal", do: "text", else: "number"}
          inputmode={if @row["type"] == "subtotal", do: "decimal", else: "numeric"}
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

  defp condition_fields(%{row: %{"type" => "has_any"}} = assigns) do
    ~H"""
    <.list_and_count row={@row} index={@index} products={@products} target={@target} kind="condition" />
    """
  end

  defp condition_fields(%{row: %{"type" => "first_order"}} = assigns) do
    ~H"""
    <p class="text-xs text-base-content/60">
      {gettext(
        "Only a signed-in customer with no previous non-cancelled website order in this branch qualifies. Choose any reward below."
      )}
    </p>
    """
  end

  defp condition_fields(%{row: %{"type" => "has"}} = assigns) do
    ~H"""
    <.product_and_count
      prefix={"builder[conditions][#{@index}]"}
      id={"builder-c#{@index}"}
      row={@row}
      products={@products}
      target={@target}
      kind="condition"
      index={@index}
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
        type={if @row["type"] == "percent", do: "number", else: "text"}
        inputmode={if @row["type"] == "percent", do: "numeric", else: "decimal"}
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
        type="text"
        inputmode="decimal"
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
      <button
        id={"builder-e#{@index}-picker"}
        type="button"
        class="btn btn-outline btn-sm"
        phx-click={JS.push_focus() |> JS.push("open_product_picker", target: @target)}
        phx-value-kind="effect"
        phx-value-index={@index}
        phx-target={@target}
      >{gettext("+ Add product")}</button>
    </div>
    """
  end

  defp effect_fields(%{row: %{"type" => "gift_any"}} = assigns) do
    ~H"""
    <.list_and_count row={@row} index={@index} products={@products} target={@target} kind="effect" />
    """
  end

  defp effect_fields(%{row: %{"type" => "gift"}} = assigns) do
    ~H"""
    <.product_and_count
      prefix={"builder[effects][#{@index}]"}
      id={"builder-e#{@index}"}
      row={@row}
      products={@products}
      target={@target}
      kind="effect"
      index={@index}
    />
    """
  end

  defp effect_fields(%{row: %{"type" => "price"}} = assigns) do
    ~H"""
    <div class="flex gap-2">
      <input type="hidden" name={"builder[effects][#{@index}][product]"} value={@row["product"]} />
      <button
        id={"builder-e#{@index}-picker"}
        type="button"
        class="btn btn-outline btn-sm flex-1"
        phx-click={JS.push_focus() |> JS.push("open_product_picker", target: @target)}
        phx-value-kind="effect"
        phx-value-index={@index}
        phx-target={@target}
      >{product_name(@products, @row["product"]) || gettext("Choose a product")}</button>
      <label class="input input-sm w-28 shrink-0">
        <input
          type="text"
          inputmode="decimal"
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

  attr :row, :map, required: true
  attr :index, :integer, required: true
  attr :products, :list, required: true
  attr :target, :any, required: true
  attr :kind, :string, required: true

  defp list_and_count(assigns) do
    assigns = assign(assigns, :prefix, "builder[#{assigns.kind}s][#{assigns.index}]")

    ~H"""
    <div class="space-y-2">
      <div class="flex flex-wrap gap-1">
        <span :for={slug <- @row["products"]} class="badge badge-primary badge-outline gap-1">
          <input type="hidden" name={@prefix <> "[products][]"} value={slug} />
          {product_name(@products, slug)}
          <button
            type="button"
            phx-click="remove_product"
            phx-target={@target}
            phx-value-kind={@kind}
            phx-value-index={@index}
            phx-value-slug={slug}
          >
            <.icon name="hero-x-mark" class="size-3" />
          </button>
        </span>
      </div>
      <input type="hidden" name={@prefix <> "[products][]"} value="" />
      <button
        id={"#{@kind}-#{@index}-picker"}
        type="button"
        class="btn btn-outline btn-sm"
        phx-click={JS.push_focus() |> JS.push("open_product_picker", target: @target)}
        phx-value-kind={@kind}
        phx-value-index={@index}
        phx-target={@target}
      >{gettext("+ Add product")}</button>
      <.input
        type="number"
        id={"#{@kind}-#{@index}-count"}
        name={@prefix <> "[count]"}
        value={@row["count"]}
        min="1"
        max="99"
        label={gettext("Number of items")}
      />
    </div>
    """
  end

  attr :prefix, :string, required: true
  attr :id, :string, required: true
  attr :row, :map, required: true
  attr :products, :list, required: true
  attr :target, :any, required: true
  attr :kind, :string, required: true
  attr :index, :integer, required: true

  defp product_and_count(assigns) do
    ~H"""
    <div class="flex gap-2">
      <input type="hidden" name={"#{@prefix}[product]"} value={@row["product"]} />
      <button
        id={"#{@id}-picker"}
        type="button"
        class="btn btn-outline btn-sm flex-1"
        phx-click={JS.push_focus() |> JS.push("open_product_picker", target: @target)}
        phx-value-kind={@kind}
        phx-value-index={@index}
        phx-target={@target}
      >{product_name(@products, @row["product"]) || gettext("Choose a product")}</button>
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

  defp certificate_error({:frontpad, "invalid_certificate"}),
    do: "Сертификат не найден или недействителен"

  defp certificate_error({:throttled, _}),
    do: "Слишком частые запросы. Повторите через несколько секунд"

  defp certificate_error(:unsupported_provider),
    do: "Проверка сертификатов этой CRM пока не поддерживается"

  defp certificate_error(:inactive_provider), do: "Выбранная CRM не подключена к заказам сайта"
  defp certificate_error(:feature_disabled), do: "Доступ к интеграции отключён"
  defp certificate_error(:invalid_code), do: "Укажите номер сертификата (не более 20 символов)"
  defp certificate_error(_), do: "Не удалось проверить сертификат в CRM"

  defp certificate_label(%{"type" => "percent", "sale" => sale}), do: "скидка #{sale}%"

  defp certificate_label(%{"type" => "amount", "amount" => amount}),
    do: "скидка #{Delivest.Money.format(amount)}"

  defp certificate_label(%{"type" => "product", "name" => name, "price" => price}),
    do: "#{name}, цена #{Delivest.Money.format(price)}"

  defp certificate_save_token(%{certificate_provider: "", certificate_original: nil}), do: nil
  defp certificate_save_token(%{certificate_provider: ""}), do: ""

  defp certificate_save_token(%{
         certificate_provider: provider,
         certificate_code: code,
         certificate_original: %{"provider" => provider, "code" => code},
         certificate_token: nil
       }),
       do: nil

  defp certificate_save_token(%{certificate_token: token}) when is_binary(token), do: token
  defp certificate_save_token(_assigns), do: :unverified
end
