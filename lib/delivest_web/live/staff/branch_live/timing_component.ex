defmodule DelivestWeb.Staff.BranchLive.TimingComponent do
  use DelivestWeb, :live_component

  alias Delivest.Identity
  alias Delivest.Net.{Categories, Products}
  alias Delivest.Oms.OrderTiming

  @impl true
  def update(assigns, socket) do
    if socket.assigns[:branch] && socket.assigns.branch.id == assigns.branch.id do
      {:ok, assign(socket, assigns)}
    else
      settings = OrderTiming.get(assigns.branch.id)
      params = params(settings, assigns.branch.info && assigns.branch.info.delivery_time)

      products = Products.list_product_options_for_branch(assigns.branch.id)

      {:ok,
       socket
       |> assign(assigns)
       |> assign(
         categories: Categories.list_branch_categories(assigns.branch.id),
         products: products,
         product_names: Map.new(products, fn {name, id} -> {id, name} end),
         params: params,
         product_ids:
           for({_name, id} <- products, Map.has_key?(params["product_minutes"], id), do: id),
         advanced_open: false,
         form: to_form(params, as: "timing")
       )}
    end
  end

  @impl true
  def handle_event("change", %{"timing" => params}, socket) do
    {:noreply, put_params(socket, params)}
  end

  def handle_event("toggle_advanced", _params, socket) do
    {:noreply, assign(socket, advanced_open: not socket.assigns.advanced_open)}
  end

  def handle_event("add_product", _params, socket) do
    id = socket.assigns.params["new_product_id"]
    known = Enum.any?(socket.assigns.products, fn {_name, product_id} -> product_id == id end)

    if known and id not in socket.assigns.product_ids do
      {:noreply, assign(socket, product_ids: socket.assigns.product_ids ++ [id])}
    else
      {:noreply, socket}
    end
  end

  def handle_event("remove_product", %{"id" => id}, socket) do
    {:noreply,
     socket
     |> assign(product_ids: List.delete(socket.assigns.product_ids, id))
     |> put_params(Map.update!(socket.assigns.params, "product_minutes", &Map.delete(&1, id)))}
  end

  def handle_event("save", %{"timing" => params}, socket) do
    params = Map.merge(socket.assigns.params, params)

    attrs =
      if params["mode"] == "calculated" do
        params
        |> Map.put(
          "category_minutes",
          only_present(params["category_minutes"], Enum.map(socket.assigns.categories, & &1.id))
        )
        |> Map.put(
          "product_minutes",
          only_present(params["product_minutes"], socket.assigns.product_ids)
        )
        |> Map.drop(["new_product_id", "travel_minutes"])
      else
        Map.take(params, ["mode", "fixed_delivery_minutes"])
      end

    case OrderTiming.update(
           Identity.fresh_staff(socket.assigns.current_staff),
           socket.assigns.branch.id,
           attrs
         ) do
      {:ok, settings} ->
        saved = params(settings, params["fixed_delivery_minutes"])

        {:noreply,
         socket
         |> put_params(saved)
         |> put_flash(:info, gettext("Order timing saved"))
         |> push_event("staff:form-saved", %{id: "branch-timing-form"})}

      {:error, _reason} ->
        {:noreply,
         socket
         |> put_params(params)
         |> put_flash(:error, gettext("Check the time settings"))
         |> push_event("staff:form-failed", %{id: "branch-timing-form"})}
    end
  end

  defp only_present(values, ids) when is_map(values),
    do: Map.take(values, ids) |> Map.reject(fn {_id, minutes} -> minutes in [nil, ""] end)

  defp only_present(_, _), do: %{}

  defp put_params(socket, params) do
    merged = Map.merge(socket.assigns.params, params)
    assign(socket, params: merged, form: to_form(merged, as: "timing"))
  end

  defp params(settings, fixed) do
    %{
      "mode" => to_string(settings.mode),
      "fixed_delivery_minutes" => fixed || 60,
      "kitchen_minutes" => settings.kitchen_minutes,
      "packing_minutes" => settings.packing_minutes,
      "category_minutes" => settings.category_minutes || %{},
      "product_minutes" => settings.product_minutes || %{},
      "new_product_id" => ""
    }
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.form
        for={@form}
        id="branch-timing-form"
        phx-target={@myself}
        phx-change="change"
        phx-submit="save"
        data-staff-dirty
        class="space-y-5"
      >
        <section class="space-y-4 rounded-box border border-base-300 bg-base-100 p-5 sm:p-6">
          <h2 class="text-lg font-semibold">{gettext("Customer delivery estimate")}</h2>
          <p class="text-sm text-base-content/70">
            {gettext("Choose how the time shown to customers is calculated.")}
          </p>
          <div class="grid gap-3 sm:grid-cols-2">
            <label class={[
              "cursor-pointer rounded-box border p-4",
              @params["mode"] == "fixed" && "border-primary bg-primary/5"
            ]}>
              <input
                id="timing-mode-fixed"
                type="radio"
                name="timing[mode]"
                value="fixed"
                checked={@params["mode"] == "fixed"}
                class="radio radio-primary radio-sm mr-2"
              />
              <span class="font-medium">{gettext("One delivery time")}</span>
              <span class="mt-1 block text-sm text-base-content/65">{gettext(
                "Show one full time from order to handover for every delivery."
              )}</span>
            </label>
            <label class={[
              "cursor-pointer rounded-box border p-4",
              @params["mode"] == "calculated" && "border-primary bg-primary/5"
            ]}>
              <input
                id="timing-mode-calculated"
                type="radio"
                name="timing[mode]"
                value="calculated"
                checked={@params["mode"] == "calculated"}
                class="radio radio-primary radio-sm mr-2"
              />
              <span class="font-medium">{gettext("Calculated time")}</span>
              <span class="mt-1 block text-sm text-base-content/65">{gettext(
                "Kitchen time plus the time to deliver to the address."
              )}</span>
            </label>
          </div>
          <.input
            field={@form[:fixed_delivery_minutes]}
            type="number"
            min="1"
            max="600"
            label={gettext("Full delivery time, minutes")}
          />
          <p class="text-sm text-base-content/60">
            {gettext(
              "Used in one-time mode. Includes cooking and delivery. This value is also editable in Delivery settings."
            )}
          </p>
        </section>

        <section
          :if={@params["mode"] == "calculated"}
          class="space-y-5 rounded-box border border-base-300 bg-base-100 p-5 sm:p-6"
        >
          <div>
            <h2 class="text-lg font-semibold">{gettext("Kitchen estimate")}</h2>
            <p class="text-sm text-base-content/70">
              {gettext(
                "Enter times for categories. Add a product only when it differs from its category."
              )}
            </p>
          </div>
          <div class="overflow-hidden rounded-box border border-base-300">
            <table class="table table-sm table-fixed w-full">
              <colgroup><col /><col class="w-28" /></colgroup>
              <thead class="bg-base-200/70">
                <tr>
                  <th scope="col" class="whitespace-normal">{gettext("Category")}</th><th scope="col">
                    {gettext("Minutes")}
                  </th>
                </tr>
              </thead>
              <tbody>
                <tr class="bg-primary/10">
                  <th scope="row" class="whitespace-normal">
                    <label for="timing_kitchen_minutes" class="font-semibold">
                      {gettext("Default preparation time")}
                      <span class="block text-xs font-normal text-base-content/65">{gettext(
                        "From starting preparation until the order is ready for handover."
                      )}</span>
                    </label>
                  </th>
                  <td>
                    <input
                      id="timing_kitchen_minutes"
                      name="timing[kitchen_minutes]"
                      value={@params["kitchen_minutes"]}
                      type="number"
                      min="1"
                      max="600"
                      required
                      phx-debounce="blur"
                      aria-label={gettext("Default preparation time, minutes")}
                      class="input input-bordered w-full min-w-0"
                    />
                  </td>
                </tr>
                <tr :for={category <- @categories}>
                  <th scope="row" class="whitespace-normal break-words font-normal">
                    <label for={"timing-category-#{category.id}"}>{category.name}</label>
                  </th>
                  <td>
                    <input
                      id={"timing-category-#{category.id}"}
                      name={"timing[category_minutes][#{category.id}]"}
                      value={@params["category_minutes"][category.id]}
                      type="number"
                      min="1"
                      max="600"
                      placeholder={to_string(@params["kitchen_minutes"])}
                      phx-debounce="blur"
                      aria-label={
                        gettext("Preparation time for %{name}, minutes", name: category.name)
                      }
                      class="input input-bordered w-full min-w-0"
                    />
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
          <p class="text-xs text-base-content/65">
            {gettext("Leave a category blank to use the default time.")}
          </p>
          <div class="border-t border-base-200 pt-4 space-y-3">
            <h3 class="font-semibold">{gettext("Product exceptions")}</h3>
            <p class="text-sm text-base-content/70">
              {gettext(
                "Add only products whose preparation time differs from their category. A blank value inherits the category time."
              )}
            </p>
            <div :if={@product_ids != []} class="overflow-hidden rounded-box border border-base-300">
              <table class="table table-sm table-fixed w-full">
                <colgroup><col /><col class="w-24 sm:w-28" /><col class="w-10" /></colgroup>
                <thead class="bg-base-200/70">
                  <tr>
                    <th scope="col">{gettext("Product")}</th><th scope="col">{gettext("Minutes")}</th><th
                      scope="col"
                      class="sr-only"
                    >
                      {gettext("Remove")}
                    </th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={id <- @product_ids}>
                    <th scope="row" class="whitespace-normal break-words font-normal">
                      <label for={"timing-product-#{id}"}>{@product_names[id]}</label>
                    </th>
                    <td>
                      <input
                        id={"timing-product-#{id}"}
                        name={"timing[product_minutes][#{id}]"}
                        value={@params["product_minutes"][id]}
                        type="number"
                        min="1"
                        max="600"
                        phx-debounce="blur"
                        aria-label={
                          gettext("Preparation time for %{name}, minutes", name: @product_names[id])
                        }
                        class="input input-bordered w-full min-w-0"
                      />
                    </td>
                    <td class="p-0 pr-1">
                      <button
                        type="button"
                        phx-click="remove_product"
                        phx-target={@myself}
                        phx-value-id={id}
                        class="btn btn-ghost btn-square"
                        aria-label={gettext("Remove time for %{name}", name: @product_names[id])}
                      ><.icon name="hero-x-mark" class="size-4" /></button>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
            <div class="flex flex-wrap gap-2">
              <select
                id="timing-add-product"
                name="timing[new_product_id]"
                class="select select-bordered flex-1 min-w-36"
              >
                <option value="">{gettext("Choose product")}</option>
                <option
                  :for={{name, id} <- @products}
                  :if={id not in @product_ids}
                  value={id}
                  selected={@params["new_product_id"] == id}
                >
                  {name}
                </option>
              </select>
              <button
                id="timing-add-product-button"
                type="button"
                phx-click="add_product"
                phx-target={@myself}
                class="btn btn-outline"
              >{gettext("Add product")}</button>
            </div>
          </div>
          <details
            id="timing-advanced"
            open={@advanced_open}
            class="rounded-box border border-base-300 bg-base-100 p-4"
          >
            <summary
              phx-click="toggle_advanced"
              phx-target={@myself}
              class="cursor-pointer font-medium"
            >
              {gettext("Advanced")}
            </summary>
            <div class="mt-4 max-w-xs space-y-2">
              <.input
                field={@form[:packing_minutes]}
                type="number"
                min="0"
                max="120"
                label={gettext("Additional buffer, minutes")}
              />
              <p class="text-xs text-base-content/65">
                {gettext(
                  "Optional extra time added after the kitchen estimate; leave 0 if not needed."
                )}
              </p>
            </div>
          </details>
          <p class="text-sm text-base-content/70">
            {gettext("Courier travel time is configured in Delivery settings.")}
            <.link navigate={~p"/staff/b/#{@branch}/delivery/zones"} class="link link-primary">
              {gettext("Open delivery settings")}
            </.link>
          </p>
        </section>
        <div class="flex justify-end">
          <button
            id="timing-save"
            type="submit"
            class="btn btn-primary"
            phx-disable-with={gettext("Saving...")}
          >{gettext("Save")}</button>
        </div>
      </.form>
    </div>
    """
  end
end
