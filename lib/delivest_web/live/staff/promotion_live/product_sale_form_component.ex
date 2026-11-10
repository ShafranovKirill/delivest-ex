defmodule DelivestWeb.Staff.PromotionLive.ProductSaleFormComponent do
  use DelivestWeb, :live_component

  alias Delivest.{Money, Net, Promo}
  alias Delivest.Promo.Promotion
  alias DelivestWeb.Staff.PromotionLive.{ProductSale, PromotionHelpers}

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)

    if socket.assigns[:form] do
      {:ok, socket}
    else
      products = Net.list_branch_products(assigns.branch_id)

      {:ok,
       socket
       |> assign(
         options: Enum.map(products, &{&1.name, &1.slug}),
         names: Map.new(products, &{&1.slug, &1.name}),
         prices: Map.new(products, &{&1.slug, &1.price}),
         sale: %ProductSale{},
         params: %{},
         default_code: "SALE#{Ecto.UUID.generate() |> String.slice(0, 8) |> String.upcase()}",
         show_errors: false
       )
       |> refresh(nil)}
    end
  end

  @impl true
  def handle_event("validate", params, socket) do
    {:noreply, socket |> take_params(params) |> refresh(:validate)}
  end

  def handle_event("save", params, socket) do
    socket = take_params(socket, params)

    with nil <- ProductSale.error(socket.assigns.sale, socket.assigns.prices),
         {:ok, promotion} <-
           Promo.create_promotion(
             socket.assigns.current_staff,
             socket.assigns.branch_id,
             promotion_params(socket.assigns)
           ) do
      send(self(), {__MODULE__, {:saved, promotion}})
      {:noreply, socket}
    else
      {:error, :forbidden} ->
        {:noreply,
         put_flash(socket, :error, gettext("You don't have permission to perform this action."))}

      _error ->
        {:noreply, socket |> assign(show_errors: true) |> refresh(:insert)}
    end
  end

  def handle_event("remove_product", %{"slug" => slug}, socket) do
    {:noreply,
     socket
     |> assign(sale: ProductSale.remove_product(socket.assigns.sale, slug))
     |> refresh(socket.assigns.form.source.action)}
  end

  defp take_params(socket, params) do
    assign(socket,
      params: Map.get(params, "promotion", %{}),
      sale: ProductSale.from_params(Map.get(params, "sale", %{}))
    )
  end

  defp refresh(socket, action) do
    changeset =
      %Promotion{branch_id: socket.assigns.branch_id}
      |> Promo.change_promotion(promotion_params(socket.assigns))
      |> Map.put(:action, action)

    assign(socket,
      form: to_form(changeset),
      new_prices: ProductSale.new_prices(socket.assigns.sale, socket.assigns.prices)
    )
  end

  defp promotion_params(assigns) do
    kind = Map.get(assigns.params, "kind", "automatic")

    %{
      "name" => name(assigns),
      "kind" => kind,
      "code" => if(kind == "public_code", do: blank_code(assigns), else: nil),
      "rules" => ProductSale.to_rules(assigns.sale),
      "combinable" => "true"
    }
  end

  defp name(%{sale: sale, names: names}), do: ProductSale.default_name(sale, names)

  defp blank_code(%{params: params, default_code: default_code}),
    do: if(String.trim(params["code"] || "") == "", do: default_code, else: params["code"])

  defp mode_label("percent"), do: gettext("Percent off")
  defp mode_label("amount"), do: gettext("Amount off")
  defp mode_label("price"), do: gettext("New price")

  defp unit("percent"), do: "%"
  defp unit(_mode), do: "₽"

  defp placeholder("percent"), do: "20"
  defp placeholder("amount"), do: "100"
  defp placeholder("price"), do: "399"

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        error: assigns.show_errors && ProductSale.error(assigns.sale, assigns.prices)
      )

    ~H"""
    <div class="h-full flex flex-col">
      <.form
        for={@form}
        id="sale-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
        class="flex flex-col h-full"
      >
        <div class="flex-1 overflow-y-auto space-y-6">
          <section id="sale-kind" class="space-y-2">
            <h3 class="font-bold">{gettext("How should customers receive it?")}</h3>
            <div class="grid gap-2 sm:grid-cols-3">
              <label
                :for={kind <- PromotionHelpers.kinds()}
                class="rounded-box border border-base-300 p-3 cursor-pointer"
              >
                <input
                  type="radio"
                  name="promotion[kind]"
                  value={kind}
                  checked={to_string(@form[:kind].value) == to_string(kind)}
                />
                <span class="font-semibold">{PromotionHelpers.kind_label(kind)}</span>
                <span class="block text-xs text-base-content/60">{PromotionHelpers.kind_hint(kind)}</span>
              </label>
            </div>
            <.input
              :if={to_string(@form[:kind].value) == "public_code"}
              field={@form[:code]}
              type="text"
              label={gettext("Promo code")}
              placeholder={@default_code}
            />
          </section>
          <section class="space-y-2">
            <h3 class="font-bold">{gettext("Which products?")}</h3>
            <div id="sale-products" class="flex flex-wrap gap-1">
              <span
                :for={slug <- @sale.products}
                class="badge badge-primary badge-outline gap-1 pr-1"
              >
                <input type="hidden" name="sale[products][]" value={slug} />
                {Map.get(@names, slug, slug)}
                <button
                  type="button"
                  class="hover:text-error"
                  phx-click="remove_product"
                  phx-value-slug={slug}
                  phx-target={@myself}
                >
                  <.icon name="hero-x-mark" class="size-3" />
                </button>
              </span>
            </div>
            <input type="hidden" name="sale[products][]" value="" />
            <select
              name="sale[add]"
              class="select w-full"
              id={"sale-add-#{length(@sale.products)}"}
            >
              <option value="">{gettext("+ Add product")}</option>
              {Phoenix.HTML.Form.options_for_select(
                Enum.reject(@options, fn {_name, slug} -> slug in @sale.products end),
                nil
              )}
            </select>
          </section>

          <section class="space-y-2">
            <h3 class="font-bold">{gettext("What discount?")}</h3>
            <div class="join w-full">
              <label
                :for={mode <- ProductSale.modes()}
                class={["join-item btn btn-sm flex-1", @sale.mode == mode && "btn-primary"]}
              >
                <input
                  type="radio"
                  class="hidden"
                  name="sale[mode]"
                  value={mode}
                  checked={@sale.mode == mode}
                />
                {mode_label(mode)}
              </label>
            </div>
            <label class="input w-full">
              <input
                type={if @sale.mode == "percent", do: "number", else: "text"}
                inputmode={if @sale.mode == "percent", do: "numeric", else: "decimal"}
                min="0"
                name="sale[value]"
                value={@sale.value}
                id="sale-value"
                placeholder={placeholder(@sale.mode)}
              />
              <span class="text-base-content/50">{unit(@sale.mode)}</span>
            </label>
          </section>

          <div
            :if={@new_prices != %{}}
            id="sale-preview"
            class="rounded-box border border-success/30 bg-success/5 p-3 text-sm space-y-1"
          >
            <p :for={slug <- @sale.products} :if={Map.has_key?(@new_prices, slug)} class="flex gap-2">
              <span class="flex-1 truncate">{Map.get(@names, slug, slug)}</span>
              <span class="line-through text-base-content/50 tabular-nums">{Money.format(
                @prices[slug]
              )}</span>
              <span class="font-bold tabular-nums">{Money.format(@new_prices[slug])}</span>
            </p>
          </div>

          <p
            :if={@error}
            id="sale-error"
            class="rounded-box border border-error/40 bg-error/5 p-3 text-sm text-error"
          >
            {@error}
          </p>
        </div>

        <div class="shrink-0 pt-4 mt-4 border-t border-base-200 flex justify-end gap-3">
          <.link patch={@patch} class="btn btn-ghost">{gettext("Cancel")}</.link>
          <button
            id="sale-save"
            type="submit"
            class="btn btn-primary"
            phx-disable-with={gettext("Saving...")}
          >
            {gettext("Save")}
          </button>
        </div>
      </.form>
    </div>
    """
  end
end
